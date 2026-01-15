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
  static final Dio _dio = Dio();
  static final Set<String> _activeDownloads = {};

  static final ValueNotifier<Map<String, double>> downloadingProgress = ValueNotifier({});

  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  Timer? _keepAliveTimer;

  bool isFileDownloading(String id) => _activeDownloads.contains(id);

  bool isFileDownloaded(String id) {
    if (!Hive.isBoxOpen('downloads_box')) return false;
    return Hive.box('downloads_box').containsKey(id);
  }

  // ... (نفس دوال الوقت والخدمة السابقة بدون تغيير) ...
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
  
  void _startBackgroundService() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) await service.startService();
    
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeDownloads.isEmpty) return;
      service.invoke('keepAlive');
      try {
        NotificationService().showProgressNotification(
          id: 888, 
          title: "مــــداد Service",
          body: "${_activeDownloads.length} file(s) downloading...",
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
  // 🚀 Core Logic: Start Download with On-the-fly Encryption
  // ---------------------------------------------------------------------------

  Future<void> startDownload({
    required String lessonId,
    required String videoTitle,
    required String courseName,
    required String subjectName,
    required String chapterName,
    String? downloadUrl,
    required Function(double) onProgress,
    required Function() onComplete,
    required Function(String) onError,
    bool isPdf = false,
    String quality = "SD",
    String duration = "", 
  }) async {
    FirebaseCrashlytics.instance.log("⬇️ Turbo Download Started: $videoTitle");
    _activeDownloads.add(lessonId);
    _startBackgroundService();
    
    // تحديث الحالة الأولية
    var currentProgress = Map<String, double>.from(downloadingProgress.value);
    currentProgress[lessonId] = 0.0;
    downloadingProgress.value = currentProgress;

    final notifService = NotificationService();
    final int notificationId = lessonId.hashCode;

    await notifService.showProgressNotification(
      id: notificationId,
      title: "Downloading: $videoTitle",
      body: "Starting...",
      progress: 0, maxProgress: 100,
    );

    try {
      await EncryptionHelper.init();
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      const String appSecret = String.fromEnvironment('APP_SECRET');

      if (userId == null) throw Exception("User authentication missing");

      // 1. الحصول على الرابط
      String? finalUrl = downloadUrl;
      if (finalUrl == null) {
        if (isPdf) {
           finalUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
        } else {
          final res = await _dio.get(
            '$_baseUrl/api/secure/get-video-id',
            queryParameters: {'lessonId': lessonId},
            options: Options(headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret}, validateStatus: (s) => s! < 500),
          );
          if (res.statusCode != 200) throw Exception(res.data['message'] ?? "Failed to get info");
          
          final data = res.data;
          if (data['availableQualities'] != null) {
            List qualities = data['availableQualities'];
            var q720 = qualities.firstWhere((q) => q['quality'] == 720, orElse: () => null);
            if (q720 != null) { finalUrl = q720['url']; quality = "720p"; }
            else if (qualities.isNotEmpty) { finalUrl = qualities.first['url']; quality = "${qualities.first['quality']}p"; }
          }
          if (finalUrl == null && data['url'] != null) finalUrl = data['url'];
        }
      }
      if (finalUrl == null) throw Exception("No link found");

      if (!isPdf) {
        String extractedDuration = _extractDurationFromUrl(finalUrl);
        if (extractedDuration.isNotEmpty) duration = extractedDuration;
      }

      // 2. تحضير المسار والملف النهائي
      final appDir = await getApplicationDocumentsDirectory();
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      // ⚠️ التغيير الجذري: لا يوجد ملف temp، نكتب في الملف المشفر مباشرة
      final savePath = '${dir.path}/$lessonId.enc';
      final saveFile = File(savePath);
      
      // فتح الملف للكتابة (Stream Sink)
      final RandomAccessFile outputFile = await saveFile.open(mode: FileMode.write);

      // دالة تحديث التقدم والإشعارات
      void updateProgress(double p) {
        var prog = Map<String, double>.from(downloadingProgress.value);
        prog[lessonId] = p;
        downloadingProgress.value = prog; 
        onProgress(p); 

        int percent = (p * 100).toInt();
        if (percent % 5 == 0) { 
          try {
            notifService.showProgressNotification(
              id: notificationId, 
              title: "Downloading: $videoTitle",
              body: "$percent%",
              progress: percent, maxProgress: 100,
            );
          } catch(e) {}
        }
      }

      // 3. التحميل والتشفير في آن واحد (Streaming)
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));
      
      // ✅ بافر لتجميع البيانات قبل التشفير
      List<int> buffer = [];

      try {
        if (isHls) {
          await _downloadAndMergeHlsWithEncryption(finalUrl, outputFile, buffer, updateProgress);
        } else {
          await _downloadStandardWithEncryption(finalUrl, outputFile, buffer, updateProgress, 
            {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret});
        }

        // ✅ تشفير وكتابة ما تبقى في البافر عند الانتهاء
        if (buffer.isNotEmpty) {
          final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
          await outputFile.writeFrom(encrypted);
          buffer.clear();
        }
      } finally {
        await outputFile.close(); // إغلاق الملف ضروري جداً
      }

      // 4. الحفظ في قاعدة البيانات
      var downloadsBox = await Hive.openBox('downloads_box');
      await downloadsBox.put(lessonId, {
        'id': lessonId,
        'title': videoTitle,
        'path': savePath,
        'course': courseName,
        'subject': subjectName,
        'chapter': chapterName,
        'type': isPdf ? 'pdf' : 'video',
        'quality': quality, 
        'duration': duration, 
        'date': DateTime.now().toIso8601String(),
        'size': await saveFile.length(),
      });

      try {
        await notifService.cancelNotification(notificationId);
        await notifService.showCompletionNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
          title: videoTitle,
          isSuccess: true,
        );
      } catch(e) {}

      FirebaseCrashlytics.instance.log("✅ Turbo Download Completed: $videoTitle");
      onComplete();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Turbo Download Failed');
      try {
        await notifService.cancelNotification(notificationId);
        await notifService.showCompletionNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
          title: videoTitle,
          isSuccess: false,
        );
      } catch (ex) {}
      
      // حذف الملف غير المكتمل
      final dir = await getApplicationDocumentsDirectory(); // إعادة بناء المسار للحذف
      // ... (يمكن تحسين منطق الحذف هنا)
      
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
  // ⚡ Streaming Logic Helpers
  // ---------------------------------------------------------------------------

  /// معالجة البافر: كلما امتلأ بحجم CHUNK، نشفره ونكتبه للملف فوراً
  Future<void> _processBuffer(List<int> buffer, RandomAccessFile sink) async {
    while (buffer.length >= EncryptionHelper.CHUNK_SIZE) {
      // اقتطاع جزء بالحجم المطلوب
      final chunk = buffer.sublist(0, EncryptionHelper.CHUNK_SIZE);
      // إزالة الجزء من البافر (الأداء هنا مقبول لأن الحجم ثابت)
      buffer.removeRange(0, EncryptionHelper.CHUNK_SIZE);
      
      // تشفير
      final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(chunk));
      
      // كتابة مباشرة للقرص
      await sink.writeFrom(encrypted);
    }
  }

  /// تحميل ملف عادي (MP4/PDF) مع التشفير الفوري
  Future<void> _downloadStandardWithEncryption(
    String url, 
    RandomAccessFile sink, 
    List<int> buffer,
    Function(double) onProgress,
    Map<String, dynamic> headers
  ) async {
    // نطلب الملف كـ Stream وليس تحميل كامل
    final response = await _dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream, // ⬅️ المفتاح للسرعة
        headers: headers,
      ),
    );

    int total = int.parse(response.headers.value(Headers.contentLengthHeader) ?? '-1');
    int received = 0;

    // قراءة الـ Stream
    Stream<Uint8List> stream = response.data.stream;
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      await _processBuffer(buffer, sink); // معالجة وتشفير ما تم تحميله
      
      received += chunk.length;
      if (total != -1) onProgress(received / total);
    }
  }

  /// تحميل HLS بالتوازي (Turbo Mode) مع التشفير الفوري
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
      int batchSize = 8; // عدد الاتصالات المتوازية

      for (int i = 0; i < total; i += batchSize) {
        int end = (i + batchSize < total) ? i + batchSize : total;
        List<String> batchUrls = tsUrls.sublist(i, end);

        // تحميل المجموعة بالتوازي
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

        // انتظار اكتمال المجموعة
        List<List<int>?> results = await Future.wait(futures);

        // الترتيب والتشفير الفوري
        for (var data in results) {
          if (data != null) {
            buffer.addAll(data); // إضافة للبافر
            await _processBuffer(buffer, sink); // تشفير وكتابة إذا امتلأ البافر
          } else {
             throw Exception("Failed segment");
          }
          done++;
          onProgress(done / total);
        }
      }
  }
}
