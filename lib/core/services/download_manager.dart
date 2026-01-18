import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../utils/encryption_helper.dart';
import 'notification_service.dart';

class DownloadManager {
  // Singleton Pattern
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  static final Dio _dio = Dio();
  static final Set<String> _activeDownloads = {};

  // لتحديث الواجهة
  static final ValueNotifier<Map<String, double>> downloadingProgress = ValueNotifier({});

  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  Timer? _keepAliveTimer;

  bool isFileDownloading(String id) => _activeDownloads.contains(id);

  bool isFileDownloaded(String id) {
    if (!Hive.isBoxOpen('downloads_box')) return false;
    return Hive.box('downloads_box').containsKey(id);
  }

  // --- دوال مساعدة للوقت ---
  String _extractDurationFromUrl(String url) {
    try {
      final regex = RegExp(r'(?:dur%3D|dur=)(\d+(\.\d+)?)');
      final match = regex.firstMatch(url);
      if (match != null) {
        final secondsString = match.group(1); 
        if (secondsString != null) {
          return _formatDuration(double.parse(secondsString).toInt());
        }
      }
    } catch (e) {}
    return ""; 
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = totalSeconds % 60;
    return hours > 0 
        ? "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}"
        : "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }
  
  // --- خدمة الخلفية ---
  void _startBackgroundService() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) await service.startService();
    
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeDownloads.isEmpty) return;
      service.invoke('keepAlive');
      try {
        // إشعار عام بالخدمة (صامت)
        NotificationService().showProgressNotification(
          id: 888, 
          title: "مــــداد Active",
          body: "${_activeDownloads.length} lesson(s) downloading...",
          progress: 0, maxProgress: 0, 
        );
      } catch (e) {}
    });
  }

  void _stopBackgroundService() async {
    if (_activeDownloads.isEmpty) {
      _keepAliveTimer?.cancel();
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      try { await NotificationService().cancelNotification(888); } catch (e) {}
    }
  }

  // ---------------------------------------------------------------------------
  // 🚀 Core Logic: Start Download (Video + Audio Split Support)
  // ---------------------------------------------------------------------------

  Future<void> startDownload({
    required String lessonId,
    required String videoTitle,
    required String courseName,
    required String subjectName,
    required String chapterName,
    String? downloadUrl,
    String? audioUrl, // ✅ رابط الصوت الاختياري
    required String quality,
    String duration = "", 
    
    required Function(double) onProgress,
    required Function() onComplete,
    required Function(String) onError,
    bool isPdf = false,
  }) async {
    FirebaseCrashlytics.instance.log("⬇️ Download Started: $videoTitle (Quality: $quality)");
    _activeDownloads.add(lessonId);
    _startBackgroundService();
    
    // تهيئة حالة التقدم
    var currentProgressMap = Map<String, double>.from(downloadingProgress.value);
    currentProgressMap[lessonId] = 0.0;
    downloadingProgress.value = currentProgressMap;

    final notifService = NotificationService();
    final int notificationId = lessonId.hashCode;

    await notifService.showProgressNotification(
      id: notificationId,
      title: "Downloading: $videoTitle",
      body: "Preparing...",
      progress: 0, maxProgress: 100,
    );

    try {
      await EncryptionHelper.init();
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      const String appSecret = String.fromEnvironment('APP_SECRET');

      if (userId == null) throw Exception("User authentication missing");

      // 1. تجهيز الروابط (إذا لم يتم تمريرها)
      String? finalVideoUrl = downloadUrl;
      String? finalAudioUrl = audioUrl;

      if (finalVideoUrl == null && !isPdf) {
          // منطق جلب الرابط في حال لم يتم تمريره (Fall-back)
          // هذا الجزء يعمل في حال استدعاء الدالة بدون روابط جاهزة
          // (يفضل دائماً تمرير الروابط من ChapterContentsScreen)
          final res = await _dio.get(
            '$_baseUrl/api/secure/get-video-id',
            queryParameters: {'lessonId': lessonId},
            options: Options(headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret}, validateStatus: (s) => s! < 500),
          );
          if (res.statusCode != 200) throw Exception(res.data['message'] ?? "Failed to get info");
          
          final data = res.data;
          // منطق بسيط لجلب رابط واحد إذا لم يتم التمرير
          if (data['url'] != null) finalVideoUrl = data['url'];
      } else if (isPdf && finalVideoUrl == null) {
          finalVideoUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
      }

      if (finalVideoUrl == null) throw Exception("No download link found");

      if (!isPdf && duration.isEmpty) {
        String extractedDuration = _extractDurationFromUrl(finalVideoUrl);
        if (extractedDuration.isNotEmpty) duration = extractedDuration;
      }

      // 2. تحضير المجلدات والمسارات
      final appDir = await getApplicationDocumentsDirectory();
      // تنظيف الأسماء من الرموز
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      // مسار الفيديو
      final String videoFileName = isPdf ? "$lessonId.pdf.enc" : "vid_${lessonId}_$quality.enc";
      final String videoSavePath = '${dir.path}/$videoFileName';
      
      // مسار الصوت (إذا وجد)
      String? audioSavePath;
      if (finalAudioUrl != null) {
        audioSavePath = '${dir.path}/aud_${lessonId}_hq.enc';
      }

      // 3. إدارة التقدم المدمج (Video + Audio)
      // نستخدم متغيرات لتتبع تقدم كل ملف على حدة
      double videoProgressVal = 0.0;
      double audioProgressVal = 0.0;

      // دالة لتحديث التقدم الكلي والإشعار
      void updateAggregatedProgress() {
        // إذا كان هناك صوت، نعطي الفيديو وزن 80% والصوت 20%
        // إذا فيديو فقط، الفيديو 100%
        double total = 0.0;
        if (finalAudioUrl != null) {
          total = (videoProgressVal * 0.8) + (audioProgressVal * 0.2);
        } else {
          total = videoProgressVal;
        }

        // تحديث الواجهة
        var progMap = Map<String, double>.from(downloadingProgress.value);
        progMap[lessonId] = total;
        downloadingProgress.value = progMap;
        onProgress(total);

        // تحديث الإشعار (كل 5% لتقليل الضغط)
        int percent = (total * 100).toInt();
        if (percent % 2 == 0) { 
          notifService.showProgressNotification(
            id: notificationId, 
            title: "Downloading: $videoTitle",
            body: "$percent%", // لا نفضح وجود ملفين، فقط النسبة المئوية
            progress: percent, maxProgress: 100,
          );
        }
      }

      // 4. تشغيل مهام التحميل بالتوازي
      final List<Future> downloadTasks = [];

      // أ) مهمة تحميل الفيديو
      downloadTasks.add(_performDownloadTask(
        url: finalVideoUrl,
        savePath: videoSavePath,
        headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret},
        onProgress: (p) {
          videoProgressVal = p;
          updateAggregatedProgress();
        }
      ));

      // ب) مهمة تحميل الصوت (إن وجد)
      if (finalAudioUrl != null && audioSavePath != null) {
        downloadTasks.add(_performDownloadTask(
          url: finalAudioUrl,
          savePath: audioSavePath,
          headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret},
          onProgress: (p) {
            audioProgressVal = p;
            updateAggregatedProgress();
          }
        ));
      }

      // انتظار اكتمال جميع الملفات
      await Future.wait(downloadTasks);

      // 5. الحفظ في قاعدة البيانات
      var downloadsBox = await Hive.openBox('downloads_box');
      await downloadsBox.put(lessonId, {
        'id': lessonId,
        'title': videoTitle,
        'path': videoSavePath,        // الفيديو
        'audioPath': audioSavePath,   // ✅ الصوت (قد يكون null)
        'course': courseName,
        'subject': subjectName,
        'chapter': chapterName,
        'type': isPdf ? 'pdf' : 'video',
        'quality': quality, 
        'duration': duration, 
        'date': DateTime.now().toIso8601String(),
        'size': await File(videoSavePath).length(), // حجم الفيديو فقط للعرض
      });

      // إشعار الاكتمال
      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: true,
      );

      FirebaseCrashlytics.instance.log("✅ Download Completed: $videoTitle");
      onComplete();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Execution Failed');
      
      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: false,
      );
      
      // تنظيف الملفات التالفة
      // (يمكن إضافة كود لحذف الملفات التي تم إنشاؤها جزئياً هنا)

      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
      _stopBackgroundService();
    }
  }

  // ---------------------------------------------------------------------------
  // 🛠️ Private Helper: Single File Downloader & Encrypter
  // ---------------------------------------------------------------------------

  Future<void> _performDownloadTask({
    required String url,
    required String savePath,
    required Map<String, dynamic> headers,
    required Function(double) onProgress,
  }) async {
    final saveFile = File(savePath);
    final RandomAccessFile outputFile = await saveFile.open(mode: FileMode.write);
    
    // بافر محلي لهذه المهمة
    List<int> buffer = [];

    try {
      bool isHls = url.contains('.m3u8') || url.contains('.m3u');

      if (isHls) {
        await _downloadAndMergeHlsWithEncryption(url, outputFile, buffer, onProgress);
      } else {
        await _downloadStandardWithEncryption(url, outputFile, buffer, onProgress, headers);
      }

      // تشفير وكتابة ما تبقى في البافر
      if (buffer.isNotEmpty) {
        final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
        await outputFile.writeFrom(encrypted);
        buffer.clear();
      }
    } finally {
      await outputFile.close();
    }
  }

  /// معالجة البافر: تشفير وكتابة
  Future<void> _processBuffer(List<int> buffer, RandomAccessFile sink) async {
    while (buffer.length >= EncryptionHelper.CHUNK_SIZE) {
      final chunk = buffer.sublist(0, EncryptionHelper.CHUNK_SIZE);
      buffer.removeRange(0, EncryptionHelper.CHUNK_SIZE);
      
      final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(chunk));
      await sink.writeFrom(encrypted);
    }
  }

  /// تحميل ملف عادي (MP4/PDF/Audio)
  Future<void> _downloadStandardWithEncryption(
    String url, 
    RandomAccessFile sink, 
    List<int> buffer,
    Function(double) onProgress,
    Map<String, dynamic> headers
  ) async {
    final response = await _dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
      ),
    );

    int total = int.parse(response.headers.value(Headers.contentLengthHeader) ?? '-1');
    int received = 0;

    Stream<Uint8List> stream = response.data.stream;
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      await _processBuffer(buffer, sink);
      
      received += chunk.length;
      if (total != -1) onProgress(received / total);
    }
  }

  /// تحميل HLS (Turbo Mode)
  Future<void> _downloadAndMergeHlsWithEncryption(
    String m3u8Url, 
    RandomAccessFile sink, 
    List<int> buffer,
    Function(double) onProgress
  ) async {
      final response = await _dio.get(m3u8Url);
      final content = response.data.toString();
      final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1);
      
      List<String> tsUrls = [];
      for (var line in content.split('\n')) {
        line = line.trim();
        if (line.isNotEmpty && !line.startsWith('#')) tsUrls.add(line.startsWith('http') ? line : baseUrl + line);
      }
      
      if (tsUrls.isEmpty) throw Exception("No TS segments");
      
      int total = tsUrls.length;
      int done = 0;
      int batchSize = 8; 

      for (int i = 0; i < total; i += batchSize) {
        int end = (i + batchSize < total) ? i + batchSize : total;
        List<String> batchUrls = tsUrls.sublist(i, end);

        List<Future<List<int>?>> futures = batchUrls.map((url) async {
          try {
            final rs = await _dio.get<List<int>>(
              url, 
              options: Options(
                responseType: ResponseType.bytes,
                sendTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 20),
              )
            );
            return rs.data;
          } catch (e) {
            return null;
          }
        }).toList();

        List<List<int>?> results = await Future.wait(futures);

        for (var data in results) {
          if (data != null) {
            buffer.addAll(data); 
            await _processBuffer(buffer, sink); 
          } else {
             throw Exception("Failed segment");
          }
          done++;
          onProgress(done / total);
        }
      }
  }
}
