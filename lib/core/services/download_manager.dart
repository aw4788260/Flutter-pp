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
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  // ✅ نستخدم Dio مع إعدادات مهلة أطول
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  static final Set<String> _activeDownloads = {};
  static final ValueNotifier<Map<String, double>> downloadingProgress = ValueNotifier({});
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  Timer? _keepAliveTimer;

  bool isFileDownloading(String id) => _activeDownloads.contains(id);

  bool isFileDownloaded(String id) {
    if (!Hive.isBoxOpen('downloads_box')) return false;
    return Hive.box('downloads_box').containsKey(id);
  }

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
        // إشعار صامت لاستمرار الخدمة
        NotificationService().showProgressNotification(
          id: 888, 
          title: "مــــداد Service",
          body: "Downloading ${_activeDownloads.length} file(s)...",
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
  // 🚀 Start Download Logic
  // ---------------------------------------------------------------------------

  Future<void> startDownload({
    required String lessonId,
    required String videoTitle,
    required String courseName,
    required String subjectName,
    required String chapterName,
    String? downloadUrl,
    String? audioUrl,
    required Function(double) onProgress,
    required Function() onComplete,
    required Function(String) onError,
    bool isPdf = false,
    String quality = "SD",
    String duration = "", 
  }) async {
    FirebaseCrashlytics.instance.log("⬇️ Download Started: $videoTitle");
    _activeDownloads.add(lessonId);
    _startBackgroundService();
    
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

      if (userId == null) throw Exception("User auth missing");

      // 1. تجهيز الروابط
      String? finalVideoUrl = downloadUrl;
      String? finalAudioUrl = audioUrl;

      if (finalVideoUrl == null) {
        if (isPdf) {
           finalVideoUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
        } else {
           // Fallback logic
           final res = await _dio.get(
            '$_baseUrl/api/secure/get-video-id',
            queryParameters: {'lessonId': lessonId},
            options: Options(headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret}),
          );
          if (res.statusCode == 200 && res.data['url'] != null) {
             finalVideoUrl = res.data['url'];
          }
        }
      }
      if (finalVideoUrl == null) throw Exception("Link not found");

      if (!isPdf && duration.isEmpty) {
        String ext = _extractDurationFromUrl(finalVideoUrl);
        if (ext.isNotEmpty) duration = ext;
      }

      // 2. تحضير المسارات
      final appDir = await getApplicationDocumentsDirectory();
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      final String videoFileName = isPdf ? "$lessonId.pdf.enc" : "vid_${lessonId}_$quality.enc";
      final String videoSavePath = '${dir.path}/$videoFileName';
      
      String? audioSavePath;
      if (finalAudioUrl != null) {
        audioSavePath = '${dir.path}/aud_${lessonId}_hq.enc';
      }

      // 3. متغيرات تتبع التقدم المدمج
      double vidProg = 0.0;
      double audProg = 0.0;

      void updateAggregatedProgress() {
        double total = (finalAudioUrl != null) 
            ? (vidProg * 0.85) + (audProg * 0.15) // وزن أكبر للفيديو
            : vidProg;
            
        var prog = Map<String, double>.from(downloadingProgress.value);
        prog[lessonId] = total;
        downloadingProgress.value = prog; 
        onProgress(total);

        int percent = (total * 100).toInt();
        // تحديث الإشعار كل 2%
        if (percent % 2 == 0) { 
          notifService.showProgressNotification(
            id: notificationId, 
            title: "Downloading: $videoTitle",
            body: "$percent%",
            progress: percent, maxProgress: 100,
          );
        }
      }

      // 4. بدء التحميل بالتوازي
      final List<Future> tasks = [];
      
      // مهمة الفيديو
      tasks.add(_downloadFileSmartly(
        url: finalVideoUrl,
        savePath: videoSavePath,
        headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret},
        onProgress: (p) { vidProg = p; updateAggregatedProgress(); }
      ));

      // مهمة الصوت (إن وجد)
      if (finalAudioUrl != null && audioSavePath != null) {
        tasks.add(_downloadFileSmartly(
          url: finalAudioUrl,
          savePath: audioSavePath,
          headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret},
          onProgress: (p) { audProg = p; updateAggregatedProgress(); }
        ));
      }

      await Future.wait(tasks);

      // 5. الحفظ
      var downloadsBox = await Hive.openBox('downloads_box');
      await downloadsBox.put(lessonId, {
        'id': lessonId,
        'title': videoTitle,
        'path': videoSavePath,
        'audioPath': audioSavePath,
        'course': courseName,
        'subject': subjectName,
        'chapter': chapterName,
        'type': isPdf ? 'pdf' : 'video',
        'quality': quality,
        'duration': duration,
        'date': DateTime.now().toIso8601String(),
        'size': await File(videoSavePath).length(),
      });

      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: true,
      );

      FirebaseCrashlytics.instance.log("✅ Download Success: $videoTitle");
      onComplete();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Smart Download Failed');
      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: false,
      );
      onError("Download failed: Network error or timeout.");
    } finally {
      _activeDownloads.remove(lessonId);
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
      _stopBackgroundService();
    }
  }

  // ---------------------------------------------------------------------------
  // 🛠️ Smart Downloader (Chunked + Retry + Encrypt)
  // ---------------------------------------------------------------------------

  Future<void> _downloadFileSmartly({
    required String url,
    required String savePath,
    required Map<String, dynamic> headers,
    required Function(double) onProgress,
  }) async {
    // التحقق من HLS
    if (url.contains('.m3u8') || url.contains('.m3u')) {
      final saveFile = File(savePath);
      final sink = await saveFile.open(mode: FileMode.write);
      List<int> buffer = [];
      try {
         await _downloadHls(url, sink, buffer, onProgress);
         // Flush buffer
         if (buffer.isNotEmpty) {
           final enc = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
           await sink.writeFrom(enc);
         }
      } finally {
        await sink.close();
      }
      return;
    }

    // ✅ التحميل الذكي للملفات العادية (Chunked Download)
    // 1. معرفة حجم الملف الكلي
    int totalBytes = 0;
    try {
      final headRes = await _dio.head(url, options: Options(headers: headers));
      totalBytes = int.parse(headRes.headers.value(Headers.contentLengthHeader) ?? '0');
    } catch (e) {
      // إذا فشل الـ HEAD، نحاول GET لـ 1 بايت
      try {
        final rangeRes = await _dio.get(url, options: Options(headers: {...headers, 'Range': 'bytes=0-0'}));
        final rangeHeader = rangeRes.headers.value(Headers.contentRangeHeader) ?? "";
        if (rangeHeader.contains("/")) {
           totalBytes = int.parse(rangeHeader.split("/").last);
        }
      } catch (_) {}
    }

    // إذا لم نستطع معرفة الحجم، نستخدم الطريقة القديمة (Stream عادي)
    if (totalBytes <= 0) {
      final saveFile = File(savePath);
      final sink = await saveFile.open(mode: FileMode.write);
      List<int> buffer = [];
      try {
        await _downloadStreamBasic(url, sink, buffer, onProgress, headers);
        if (buffer.isNotEmpty) {
           final enc = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
           await sink.writeFrom(enc);
        }
      } finally {
        await sink.close();
      }
      return;
    }

    // ✅ تقسيم الملف إلى قطع (Chunks) لتجنب انقطاع الاتصال
    // حجم القطعة = 5 ميجابايت (توازن جيد بين السرعة والأمان)
    const int chunkSize = 5 * 1024 * 1024; 
    int downloadedBytes = 0;
    
    final saveFile = File(savePath);
    // نفتح الملف بوضع append لنضيف عليه
    final sink = await saveFile.open(mode: FileMode.write);
    List<int> buffer = [];

    try {
      while (downloadedBytes < totalBytes) {
        int start = downloadedBytes;
        int end = min(start + chunkSize - 1, totalBytes - 1);
        
        // محاولة تحميل القطعة (مع Retry)
        bool chunkSuccess = false;
        int retries = 3;

        while (retries > 0 && !chunkSuccess) {
          try {
            await _downloadChunkAndEncrypt(
              url: url,
              start: start,
              end: end,
              headers: headers,
              sink: sink,
              buffer: buffer,
            );
            chunkSuccess = true;
            downloadedBytes += (end - start + 1);
            onProgress(downloadedBytes / totalBytes);
          } catch (e) {
            retries--;
            if (retries == 0) throw Exception("Failed to download chunk $start-$end after 3 retries");
            await Future.delayed(const Duration(seconds: 1)); // انتظار قبل المحاولة
            print("⚠️ Retrying chunk... ($retries left)");
          }
        }
      }

      // تشفير ما تبقى في البافر النهائي
      if (buffer.isNotEmpty) {
        final enc = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
        await sink.writeFrom(enc);
        buffer.clear();
      }

    } finally {
      await sink.close();
    }
  }

  /// تحميل قطعة واحدة وتشفيرها
  Future<void> _downloadChunkAndEncrypt({
    required String url,
    required int start,
    required int end,
    required Map<String, dynamic> headers,
    required RandomAccessFile sink,
    required List<int> buffer,
  }) async {
    final response = await _dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          ...headers,
          'Range': 'bytes=$start-$end', // ⬅️ السر هنا: طلب جزء محدد
        },
      ),
    );

    Stream<Uint8List> stream = response.data.stream;
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      // تشفير وكتابة فورية إذا امتلأ البافر (512KB)
      while (buffer.length >= EncryptionHelper.CHUNK_SIZE) {
        final block = buffer.sublist(0, EncryptionHelper.CHUNK_SIZE);
        buffer.removeRange(0, EncryptionHelper.CHUNK_SIZE);
        final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(block));
        await sink.writeFrom(encrypted);
      }
    }
  }

  // --- دوال التحميل القديمة (للحالات الخاصة) ---

  Future<void> _downloadStreamBasic(String url, RandomAccessFile sink, List<int> buffer, Function(double) onProgress, Map<String, dynamic> headers) async {
    final response = await _dio.get(
      url,
      options: Options(responseType: ResponseType.stream, headers: headers),
    );
    int total = int.parse(response.headers.value(Headers.contentLengthHeader) ?? '-1');
    int received = 0;
    Stream<Uint8List> stream = response.data.stream;
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      while (buffer.length >= EncryptionHelper.CHUNK_SIZE) {
        final block = buffer.sublist(0, EncryptionHelper.CHUNK_SIZE);
        buffer.removeRange(0, EncryptionHelper.CHUNK_SIZE);
        final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(block));
        await sink.writeFrom(encrypted);
      }
      received += chunk.length;
      if (total != -1) onProgress(received / total);
    }
  }

  Future<void> _downloadHls(String m3u8Url, RandomAccessFile sink, List<int> buffer, Function(double) onProgress) async {
     // (نفس منطق HLS السابق ولكن مع تحسين بسيط في الترتيب)
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
       int end = min(i + batchSize, total);
       List<String> batchUrls = tsUrls.sublist(i, end);
       List<Future<List<int>?>> futures = batchUrls.map((url) async {
         try {
           final rs = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 15)));
           return rs.data;
         } catch (e) { return null; }
       }).toList();

       List<List<int>?> results = await Future.wait(futures);
       
       for (var data in results) {
         if (data != null) {
           buffer.addAll(data); 
           while (buffer.length >= EncryptionHelper.CHUNK_SIZE) {
             final block = buffer.sublist(0, EncryptionHelper.CHUNK_SIZE);
             buffer.removeRange(0, EncryptionHelper.CHUNK_SIZE);
             final enc = EncryptionHelper.encryptBlock(Uint8List.fromList(block));
             await sink.writeFrom(enc);
           }
         }
         done++;
         onProgress(done / total);
       }
     }
  }
}
