import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_background_service/flutter_background_service.dart';

import '../utils/encryption_helper.dart';
import 'notification_service.dart';

class DownloadManager {
  static final Dio _dio = Dio();
  static final Set<String> _activeDownloads = {};

  static final ValueNotifier<Map<String, double>> downloadingProgress = ValueNotifier({});

  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  Timer? _keepAliveTimer;

  bool isFileDownloading(String id) {
    return _activeDownloads.contains(id);
  }

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
          final double totalSeconds = double.parse(secondsString);
          return _formatDuration(totalSeconds.toInt());
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to parse duration from URL');
    }
    return ""; 
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    } else {
      return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    }
  }

  // ---------------------------------------------------------------------------
  // إدارة خدمة الخلفية (Background Service)
  // ---------------------------------------------------------------------------
  
  void _startBackgroundService() async {
    final service = FlutterBackgroundService();
    
    // تشغيل الخدمة إذا لم تكن تعمل مسبقاً
    if (!await service.isRunning()) {
      FirebaseCrashlytics.instance.log("🚀 Starting Background Service...");
      await service.startService();
    }
    
    // إرسال إشارة "أنا أعمل" للخدمة (Watchdog) وتحديث الإشعار الرئيسي للخدمة
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // إذا لم تكن هناك تحميلات نشطة، لا داعي لتحديث الإشعار أو إبقاء الخدمة حية هنا
      if (_activeDownloads.isEmpty) return;

      service.invoke('keepAlive');
      
      try {
        // ✅ تحديث إشعار الخدمة الرئيسي (888) ليعكس عدد التحميلات الجارية
        NotificationService().showProgressNotification(
          id: 888, 
          title: "مــــداد Service",
          body: "${_activeDownloads.length} file(s) downloading...",
          progress: 0,
          maxProgress: 0, // Indeterminate
        );
      } catch (e, s) {
         FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to update background service notification');
      }
    });
  }

  void _stopBackgroundService() async {
    // نوقف الخدمة فقط إذا لم يعد هناك أي تحميل نشط
    if (_activeDownloads.isEmpty) {
      FirebaseCrashlytics.instance.log("🛑 Stopping Background Service (No active downloads)");
      _keepAliveTimer?.cancel();
      final service = FlutterBackgroundService();
      
      service.invoke('stopService');
      
      // ✅ إلغاء إشعار الخدمة الرئيسي (888) فوراً
      try {
        await NotificationService().cancelNotification(888);
      } catch (e, s) {
        FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to cancel background notification');
      }
    }
  }

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
    FirebaseCrashlytics.instance.log("⬇️ Start Download Requested: $videoTitle ($lessonId)");
    
    _activeDownloads.add(lessonId);
    
    // ✅ تشغيل الخدمة
    _startBackgroundService();
    
    var currentProgress = Map<String, double>.from(downloadingProgress.value);
    currentProgress[lessonId] = 0.0;
    downloadingProgress.value = currentProgress;

    final notifService = NotificationService();
    
    // ✅ إنشاء ID فريد لهذا الملف
    final int notificationId = lessonId.hashCode;

    // إظهار إشعار البدء لهذا الملف
    try {
      await notifService.showProgressNotification(
        id: notificationId,
        title: "Downloading: $videoTitle",
        body: "Starting...",
        progress: 0,
        maxProgress: 100,
      );
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to show start notification');
    }

    try {
      await EncryptionHelper.init();

      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      
      // 🔒 التعديل: جلب الرمز السري من متغيرات البيئة فقط
      const String appSecret = String.fromEnvironment('APP_SECRET');
      if (appSecret.isEmpty) {
         FirebaseCrashlytics.instance.log("⚠️ APP_SECRET is empty from environment!");
      }

      if (userId == null) throw Exception("User authentication missing");

      String? finalUrl = downloadUrl;

      // 1. جلب الرابط
      if (finalUrl == null) {
        if (isPdf) {
           finalUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
        } else {
          final res = await _dio.get(
            '$_baseUrl/api/secure/get-video-id',
            queryParameters: {'lessonId': lessonId},
            options: Options(headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret}, validateStatus: (s) => s! < 500),
          );

          if (res.statusCode != 200) {
             FirebaseCrashlytics.instance.log("❌ Failed to get video URL. Status: ${res.statusCode}, Body: ${res.data}");
             throw Exception(res.data['message'] ?? "Failed to get info");
          }

          final data = res.data;
          if (data['youtube_video_id'] != null && (data['availableQualities'] == null || (data['availableQualities'] as List).isEmpty)) {
             throw Exception("YouTube videos cannot be downloaded offline.");
          }

          if (data['availableQualities'] != null) {
            List qualities = data['availableQualities'];
            var q720 = qualities.firstWhere((q) => q['quality'] == 720, orElse: () => null);
            if (q720 != null) { finalUrl = q720['url']; quality = "720p"; }
            else if (qualities.isNotEmpty) { finalUrl = qualities.first['url']; quality = "${qualities.first['quality']}p"; }
          }
          if (finalUrl == null && data['url'] != null) finalUrl = data['url'];
        }
      }

      if (finalUrl == null) throw Exception("No valid download link found");

      if (!isPdf) {
        String extractedDuration = _extractDurationFromUrl(finalUrl);
        if (extractedDuration.isNotEmpty) duration = extractedDuration;
      }

      // 2. المسارات
      final appDir = await getApplicationDocumentsDirectory();
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      final tempPath = '${dir.path}/$lessonId.temp';
      final savePath = '${dir.path}/$lessonId.enc';
      File tempFile = File(tempPath);
      
      // ✅ تصحيح: استخدام try-catch عند حذف الملفات لتجنب الكراش
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (e) { /* ignore */ }

      Function(double) internalOnProgress = (p) {
        var prog = Map<String, double>.from(downloadingProgress.value);
        prog[lessonId] = p;
        downloadingProgress.value = prog; 
        onProgress(p); 

        // تحديث الإشعار الخاص بهذا الملف
        int percent = (p * 100).toInt();
        if (percent % 5 == 0) { // Update notification less frequently to avoid flooding logs/UI
          try {
            notifService.showProgressNotification(
              id: notificationId, 
              title: "Downloading: $videoTitle",
              body: "$percent%",
              progress: percent,
              maxProgress: 100,
            );
          } catch(e) {/* ignore */}
        }
      };

      // 3. التحميل
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));
      FirebaseCrashlytics.instance.log("📡 Download Mode: ${isHls ? 'HLS (Parallel)' : 'Standard DIO'}");

      if (isHls) {
        await _downloadAndMergeHls(finalUrl, tempPath, internalOnProgress);
      } else {
        await _dio.download(
          finalUrl,
          tempPath,
          options: Options(headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret}),
          onReceiveProgress: (r, t) { if (t != -1) internalOnProgress(r / t); },
        );
      }

      // التشفير
      try {
        await notifService.showProgressNotification(
          id: notificationId,
          title: "Processing: $videoTitle",
          body: "Encrypting...",
          progress: 0,
          maxProgress: 0,
        );
      } catch (e) {}

      if (await tempFile.exists()) {
        if ((await tempFile.length()) < (isPdf ? 100 : 10240)) { 
          // ✅ تصحيح: حذف آمن
          try { await tempFile.delete(); } catch(e) {}
          throw Exception("File too small");
        }
        await _encryptFileStream(tempFile, File(savePath));
        // ✅ تصحيح: حذف آمن
        try { await tempFile.delete(); } catch(e) {} 
      } else {
        throw Exception("Temp file missing");
      }

      // الحفظ
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
        'size': File(savePath).lengthSync(),
      });

      // 1. إلغاء إشعار التقدم
      try {
        await notifService.cancelNotification(notificationId);
        // ✅ 2. تصحيح: استخدام remainder لتجنب تجاوز حدود 32-bit integer
        await notifService.showCompletionNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
          title: videoTitle,
          isSuccess: true,
        );
      } catch(e, s) {
         FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to show completion notification');
      }

      FirebaseCrashlytics.instance.log("✅ Download Completed: $videoTitle");
      onComplete();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed for $videoTitle');
      
      try {
        await notifService.cancelNotification(notificationId);
        // ✅ تصحيح: استخدام remainder هنا أيضاً
        await notifService.showCompletionNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
          title: videoTitle,
          isSuccess: false,
        );
      } catch (ex) {}
      
      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
      
      // إيقاف الخدمة وإلغاء الإشعار المجمع (888)
      _stopBackgroundService();
    }
  }

  Future<void> _encryptFileStream(File inputFile, File outputFile) async {
    await EncryptionHelper.init();
    var rafRead = await inputFile.open(mode: FileMode.read);
    var rafWrite = await outputFile.open(mode: FileMode.write);
    try {
       int len = await inputFile.length();
       int read = 0;
       
       // ✅ التغيير هنا: استخدام EncryptionHelper.CHUNK_SIZE بدلاً من القيمة الثابتة
       // هذا يجعل العملية تستخدم 512KB (أو أي قيمة نحددها هناك) تلقائياً
       while(read < len) {
         var chunk = await rafRead.read(min(EncryptionHelper.CHUNK_SIZE, len - read));
         if(chunk.isEmpty) break;
         await rafWrite.writeFrom(EncryptionHelper.encryptBlock(chunk));
         read += chunk.length;
       }
    } finally { await rafRead.close(); await rafWrite.flush(); await rafWrite.close(); }
  }

  // ✅ التعديل 2: تحميل ملفات HLS بالتوازي (Turbo Speed)
  Future<void> _downloadAndMergeHls(String m3u8Url, String outputPath, Function(double) onProgress) async {
      FirebaseCrashlytics.instance.log("🚀 Starting Parallel HLS Download: $m3u8Url");
      
      final response = await _dio.get(m3u8Url);
      final content = response.data.toString();
      final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1);
      
      List<String> tsUrls = [];
      for (var line in content.split('\n')) {
        line = line.trim();
        if (line.isNotEmpty && !line.startsWith('#')) tsUrls.add(line.startsWith('http') ? line : baseUrl + line);
      }
      
      if (tsUrls.isEmpty) {
         FirebaseCrashlytics.instance.recordError(Exception("No segments"), null, reason: 'HLS has no TS segments');
         throw Exception("No TS segments");
      }
      
      final outputFile = File(outputPath);
      final sink = outputFile.openWrite(mode: FileMode.writeOnlyAppend);
      
      int total = tsUrls.length;
      int done = 0;
      
      // 🔥 عدد الاتصالات المتوازية (8 اتصالات تضاعف السرعة بشكل كبير)
      int batchSize = 8; 

      // نقسم الروابط إلى مجموعات (Batches)
      for (int i = 0; i < total; i += batchSize) {
        int end = (i + batchSize < total) ? i + batchSize : total;
        List<String> batchUrls = tsUrls.sublist(i, end);

        // إنشاء قائمة مهام تحميل متزامنة
        List<Future<List<int>?>> futures = batchUrls.map((url) async {
          try {
            final rs = await _dio.get<List<int>>(
              url, 
              options: Options(
                responseType: ResponseType.bytes,
                sendTimeout: const Duration(seconds: 15), // زيادة المهلة لتجنب التقطيع
                receiveTimeout: const Duration(seconds: 15),
              )
            );
            return rs.data;
          } catch (e, s) {
            FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to download segment: $url');
            return null;
          }
        }).toList();

        // انتظار اكتمال المجموعة كاملة
        List<List<int>?> results = await Future.wait(futures);

        // كتابة البيانات بالترتيب الصحيح (مهم جداً لسلامة الفيديو)
        for (var data in results) {
          if (data != null) {
            sink.add(data);
          } else {
             // إذا فشل جزء، يمكن إيقاف التحميل بالكامل لضمان عدم تلف الملف
             throw Exception("Failed to download a video segment");
          }
          done++;
          onProgress(done / total);
        }
      }
      
      await sink.flush();
      await sink.close();
      FirebaseCrashlytics.instance.log("✅ HLS Merge Complete ($total segments)");
  }
}
