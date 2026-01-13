import 'dart:io';
import 'dart:async';
import 'dart:math'; 
import 'dart:typed_data'; 
import 'dart:convert'; // ✅ ضروري لـ base64UrlEncode
import 'package:flutter/foundation.dart'; 
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:encrypt/encrypt.dart' as encrypt; 
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart'; // ✅ ضروري لتشفير PDF

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

  // ✅ دالة لتوليد كلمة سر عشوائية قوية (32 بايت)
  String _generateRandomPassword() {
    final random = Random.secure();
    final values = List<int>.generate(24, (i) => random.nextInt(256));
    return base64UrlEncode(values);
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
    } catch (e) {
      // تسجيل خفيف هنا لأنه ليس خطأ حرج
      FirebaseCrashlytics.instance.log("⚠️ Duration parse warning: $e");
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
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }
      
      _keepAliveTimer?.cancel();
      _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_activeDownloads.isEmpty) return;

        service.invoke('keepAlive');
        
        NotificationService().showProgressNotification(
          id: 888, 
          title: "مــــداد Service",
          body: "${_activeDownloads.length} file(s) downloading...",
          progress: 0,
          maxProgress: 0, 
        );
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to start background service');
    }
  }

  void _stopBackgroundService() async {
    try {
      if (_activeDownloads.isEmpty) {
        _keepAliveTimer?.cancel();
        final service = FlutterBackgroundService();
        service.invoke('stopService');
        await NotificationService().cancelNotification(888);
      }
    } catch (e) {
      print("Stop Service Error: $e");
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
    // 🔍 تسجيل بدء العملية
    FirebaseCrashlytics.instance.log("⬇️ START_DOWNLOAD: $videoTitle (ID: $lessonId) | Type: ${isPdf ? 'PDF' : 'Video'}");
    
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
      progress: 0,
      maxProgress: 100,
    );

    try {
      // تهيئة التشفير
      try {
        await EncryptionHelper.init();
      } catch (e) {
        throw Exception("Encryption Init Failed: $e");
      }

      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      const String appSecret = String.fromEnvironment('APP_SECRET', defaultValue: 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only');

      if (userId == null) throw Exception("User ID missing from Hive");

      String? finalUrl = downloadUrl;

      // 1. جلب الرابط (إذا لم يكن موجوداً)
      if (finalUrl == null) {
        FirebaseCrashlytics.instance.log("🌐 Fetching URL from API for $lessonId...");
        
        if (isPdf) {
           finalUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
        } else {
          final res = await _dio.get(
            '$_baseUrl/api/secure/get-video-id',
            queryParameters: {'lessonId': lessonId},
            options: Options(headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret}, validateStatus: (s) => s! < 500),
          );

          if (res.statusCode != 200) {
             throw Exception("API Error ${res.statusCode}: ${res.data['message']}");
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

      if (finalUrl == null) throw Exception("No valid download link found after API check");

      if (!isPdf) {
        String extractedDuration = _extractDurationFromUrl(finalUrl);
        if (extractedDuration.isNotEmpty) duration = extractedDuration;
      }

      // 2. إعداد المسارات
      final appDir = await getApplicationDocumentsDirectory();
      // تنظيف الأسماء لتجنب أخطاء نظام الملفات
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      final tempPath = '${dir.path}/$lessonId.temp';
      final savePath = '${dir.path}/$lessonId.enc';
      File tempFile = File(tempPath);
      
      // حذف أي ملف مؤقت سابق
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (e) { FirebaseCrashlytics.instance.log("⚠️ Could not delete old temp file: $e"); }

      Function(double) internalOnProgress = (p) {
        // تحديث الواجهة
        var prog = Map<String, double>.from(downloadingProgress.value);
        prog[lessonId] = p;
        downloadingProgress.value = prog; 
        onProgress(p); 

        // تحديث الإشعار كل 5% لتقليل الضغط
        int percent = (p * 100).toInt();
        if (percent % 5 == 0) {
          notifService.showProgressNotification(
            id: notificationId, 
            title: "Downloading: $videoTitle",
            body: "$percent%",
            progress: percent,
            maxProgress: 100,
          );
        }
      };

      // 3. التحميل الفعلي
      FirebaseCrashlytics.instance.log("🚀 Starting download from: $finalUrl");
      
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));
      
      if (isHls) {
        await _downloadAndMergeHls(finalUrl, tempPath, internalOnProgress);
      } else {
        await _dio.download(
          finalUrl,
          tempPath,
          options: Options(
            headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret},
            receiveTimeout: const Duration(minutes: 10), // زيادة مهلة التحميل
          ),
          onReceiveProgress: (r, t) { if (t != -1) internalOnProgress(r / t); },
        );
      }

      // 4. التشفير والحفظ
      await notifService.showProgressNotification(
        id: notificationId,
        title: "Processing: $videoTitle",
        body: isPdf ? "Securing PDF..." : "Encrypting...",
        progress: 0,
        maxProgress: 0,
      );

      // ✅ توليد كلمة سر عشوائية فريدة لهذا الملف
      String uniquePassword = _generateRandomPassword();

      if (await tempFile.exists()) {
        int fileSize = await tempFile.length();
        FirebaseCrashlytics.instance.log("💾 File downloaded. Size: $fileSize bytes. Starting encryption...");

        if (fileSize < (isPdf ? 100 : 10240)) { // 100 bytes للـ PDF و 10KB للفيديو كحد أدنى
          try { await tempFile.delete(); } catch(e) {}
          throw Exception("Downloaded file is too small ($fileSize bytes). Possible corruption.");
        }

        if (isPdf) {
           // ==========================================
           // ✅ منطق تشفير PDF الجديد (Password Protection)
           // ==========================================
           try {
             final List<int> bytes = await tempFile.readAsBytes();
             final PdfDocument document = PdfDocument(inputBytes: bytes);

             // تعيين كلمة السر العشوائية التي تم توليدها
             document.security.userPassword = uniquePassword;
             document.security.ownerPassword = _generateRandomPassword(); // كلمة سر للمالك مختلفة
             document.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit; // تشفير قوي

             final List<int> encryptedBytes = await document.save();
             document.dispose();
             
             await File(savePath).writeAsBytes(encryptedBytes);
             FirebaseCrashlytics.instance.log("🔒 PDF Secured Successfully.");
           } catch (e, stack) {
             FirebaseCrashlytics.instance.recordError(e, stack, reason: "PDF Encryption Failed");
             throw Exception("PDF Security Failed: $e");
           }
        } else {
           // ==========================================
           // ✅ منطق تشفير الفيديو (AES-GCM Chunks)
           // ==========================================
           try {
             await _encryptFileStream(tempFile, File(savePath));
             FirebaseCrashlytics.instance.log("🔒 Video Encrypted Successfully.");
           } catch (e, stack) {
             FirebaseCrashlytics.instance.recordError(e, stack, reason: "Video Encryption Failed");
             throw Exception("Video Encryption Failed: $e");
           }
        }
        
        // حذف الملف المؤقت بعد النجاح
        try { await tempFile.delete(); } catch(e) {} 
      } else {
        throw Exception("Temp file missing after download completion");
      }

      // 5. تسجيل البيانات في Hive
      FirebaseCrashlytics.instance.log("📝 Saving metadata to Hive...");
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
        // ✅ تخزين كلمة السر الخاصة بهذا الملف (فقط للـ PDF)
        'file_password': isPdf ? uniquePassword : null, 
      });

      // إنهاء: إشعار النجاح
      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: true,
      );

      FirebaseCrashlytics.instance.log("✅ Download Complete: $lessonId");
      onComplete();

    } catch (e, stack) {
      // 🚨 تسجيل الخطأ بالتفصيل
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'CRITICAL: Download Failed for $lessonId');
      
      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: false,
      );
      
      onError(e.toString());
    } finally {
      // تنظيف
      _activeDownloads.remove(lessonId);
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
      
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
       while(read < len) {
         var chunk = await rafRead.read(min(64*1024, len - read));
         if(chunk.isEmpty) break;
         await rafWrite.writeFrom(EncryptionHelper.encryptBlock(chunk));
         read += chunk.length;
       }
    } finally { await rafRead.close(); await rafWrite.flush(); await rafWrite.close(); }
  }

  Future<void> _downloadAndMergeHls(String m3u8Url, String outputPath, Function(double) onProgress) async {
      try {
        final response = await _dio.get(m3u8Url);
        final content = response.data.toString();
        final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1);
        List<String> tsUrls = [];
        for (var line in content.split('\n')) {
          line = line.trim();
          if (line.isNotEmpty && !line.startsWith('#')) tsUrls.add(line.startsWith('http') ? line : baseUrl + line);
        }
        if (tsUrls.isEmpty) throw Exception("No TS segments found in M3U8");
        
        final outputFile = File(outputPath);
        final sink = outputFile.openWrite(mode: FileMode.writeOnlyAppend);
        int total = tsUrls.length;
        int done = 0;
        
        for (String url in tsUrls) {
          try {
            final rs = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
            if (rs.data != null) sink.add(rs.data!);
            done++;
            onProgress(done / total);
          } catch (e) {
            FirebaseCrashlytics.instance.log("⚠️ TS segment download failed: $url ($e)");
            // يمكن إضافة منطق إعادة المحاولة هنا
            throw e;
          }
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        throw Exception("HLS Download Failed: $e");
      }
  }
}
