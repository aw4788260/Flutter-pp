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
    } catch (e) {
      FirebaseCrashlytics.instance.log("⚠️ Failed to parse duration from URL: $e");
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
      await service.startService();
    }
    
    // إرسال إشارة "أنا أعمل" للخدمة (Watchdog) وتحديث الإشعار الرئيسي للخدمة
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      service.invoke('keepAlive');
      
      // ✅ تحديث إشعار الخدمة الرئيسي (888) ليعكس عدد التحميلات الجارية
      // هذا الإشعار ضروري للنظام ولكنه الآن مفيد للمستخدم أيضاً
      NotificationService().showProgressNotification(
        id: 888, 
        title: "مــــداد Service",
        body: "${_activeDownloads.length} file(s) downloading...",
        progress: 0,
        maxProgress: 0, // Indeterminate (بدون شريط محدد)
      );
    });
  }

  void _stopBackgroundService() {
    // نوقف الخدمة فقط إذا لم يعد هناك أي تحميل نشط
    if (_activeDownloads.isEmpty) {
      _keepAliveTimer?.cancel();
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      
      // إلغاء إشعار الخدمة الرئيسي (888) فوراً
      NotificationService().cancelNotification(888);
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
    FirebaseCrashlytics.instance.log("⬇️ Start Download: $videoTitle ($lessonId)");
    
    _activeDownloads.add(lessonId);
    
    // ✅ تشغيل الخدمة لضمان البقاء في الخلفية
    _startBackgroundService();
    
    var currentProgress = Map<String, double>.from(downloadingProgress.value);
    currentProgress[lessonId] = 0.0;
    downloadingProgress.value = currentProgress;

    final notifService = NotificationService();
    
    // ✅ إنشاء ID فريد لهذا الملف تحديداً (وليس للخدمة)
    // هذا يسمح بظهور إشعار منفصل لكل ملف
    final int notificationId = lessonId.hashCode;

    // إظهار إشعار البدء لهذا الملف
    await notifService.showProgressNotification(
      id: notificationId,
      title: "Downloading: $videoTitle",
      body: "Starting...",
      progress: 0,
      maxProgress: 100,
    );

    try {
      await EncryptionHelper.init();

      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      const String appSecret = String.fromEnvironment('APP_SECRET', defaultValue: 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only');

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

          if (res.statusCode != 200) throw Exception(res.data['message'] ?? "Failed to get info");

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
      if (await tempFile.exists()) await tempFile.delete();

      Function(double) internalOnProgress = (p) {
        var prog = Map<String, double>.from(downloadingProgress.value);
        prog[lessonId] = p;
        downloadingProgress.value = prog; 
        onProgress(p); 

        // ✅ تحديث الإشعار الخاص بهذا الملف فقط
        int percent = (p * 100).toInt();
        if (percent % 2 == 0) {
          notifService.showProgressNotification(
            id: notificationId, // ID فريد لهذا الملف
            title: "Downloading: $videoTitle",
            body: "$percent%",
            progress: percent,
            maxProgress: 100,
          );
        }
      };

      // 3. التحميل
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));
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

      // التشفير (تحديث الإشعار الخاص بالملف)
      await notifService.showProgressNotification(
        id: notificationId,
        title: "Processing: $videoTitle",
        body: "Encrypting...",
        progress: 0,
        maxProgress: 0,
      );

      if (await tempFile.exists()) {
        if ((await tempFile.length()) < (isPdf ? 100 : 10240)) { 
          await tempFile.delete();
          throw Exception("File too small");
        }
        await _encryptFileStream(tempFile, File(savePath));
        await tempFile.delete(); 
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

      // ✅ 1. إلغاء إشعار التقدم لهذا الملف
      await notifService.cancelNotification(notificationId);

      // ✅ 2. إظهار إشعار النجاح النهائي (بـ ID جديد ليبقى في السجل)
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch,
        title: videoTitle,
        isSuccess: true,
      );

      onComplete();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed');
      
      // ✅ إلغاء إشعار التقدم وإظهار إشعار الفشل
      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch,
        title: videoTitle,
        isSuccess: false,
      );
      
      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
      
      // ✅ محاولة إيقاف الخدمة إذا لم تعد هناك تحميلات أخرى
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
      final response = await _dio.get(m3u8Url);
      final content = response.data.toString();
      final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1);
      List<String> tsUrls = [];
      for (var line in content.split('\n')) {
        line = line.trim();
        if (line.isNotEmpty && !line.startsWith('#')) tsUrls.add(line.startsWith('http') ? line : baseUrl + line);
      }
      if (tsUrls.isEmpty) throw Exception("No TS segments");
      final outputFile = File(outputPath);
      final sink = outputFile.openWrite(mode: FileMode.writeOnlyAppend);
      int total = tsUrls.length;
      int done = 0;
      for (String url in tsUrls) {
        final rs = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
        if (rs.data != null) sink.add(rs.data!);
        done++;
        onProgress(done / total);
      }
      await sink.flush();
      await sink.close();
  }
}
