import 'dart:io';
import 'dart:async';
import 'dart:isolate'; // ✅ مكتبة العزل الضرورية
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/widgets.dart'; 
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt; // ✅ استيراد التشفير لاستخدامه في الخلفية

import '../utils/encryption_helper.dart';
import 'notification_service.dart';

class DownloadManager with WidgetsBindingObserver {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  DownloadManager._internal() {
    WidgetsBinding.instance.addObserver(this);
    NotificationService().cancelAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      cancelAllDownloads();
    }
  }

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  // ✅ تخزين الـ Isolates النشطة للتحكم فيها (إلغاء/قتل)
  static final Map<String, Isolate> _activeIsolates = {};
  
  static final Set<String> _activeDownloads = {};
  final Map<String, String> activeTitles = {}; 
  
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

  Future<void> cancelAllDownloads() async {
    final List<String> allIds = List.from(_activeIsolates.keys);
    for (var id in allIds) {
      await cancelDownload(id);
    }
    await NotificationService().cancelAll();
    _stopBackgroundService();
  }

  Future<void> cancelDownload(String lessonId) async {
    // ✅ الإلغاء يتم الآن عن طريق قتل الـ Isolate فوراً
    if (_activeIsolates.containsKey(lessonId)) {
      _activeIsolates[lessonId]?.kill(priority: Isolate.immediate);
      _activeIsolates.remove(lessonId);
    }
    
    _activeDownloads.remove(lessonId);
    activeTitles.remove(lessonId);
    
    var prog = Map<String, double>.from(downloadingProgress.value);
    prog.remove(lessonId);
    downloadingProgress.value = prog;

    await NotificationService().cancelNotification(lessonId.hashCode);
    
    // تنظيف الملفات غير المكتملة (اختياري، يمكن إضافته هنا إذا لزم الأمر)

    if (_activeDownloads.isEmpty) {
      _stopBackgroundService();
    }
    
    debugPrint("🛑 Download Cancelled (Isolate Killed): $lessonId");
  }
  
  void _startBackgroundService() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) await service.startService();
    
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeDownloads.isEmpty) {
         _stopBackgroundService(); 
         return;
      }
      service.invoke('keepAlive');
    });
  }

  void _stopBackgroundService() async {
    _keepAliveTimer?.cancel();
    try { await NotificationService().cancelNotification(888); } catch (e) {}

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
       service.invoke('stopService');
    }
  }

  // ---------------------------------------------------------------------------
  // 🚀 Start Download Logic (Main Thread)
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
    activeTitles[lessonId] = videoTitle; 

    FirebaseCrashlytics.instance.log("⬇️ Download Request: $videoTitle");
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
      // التأكد من تهيئة التشفير للحصول على المفتاح
      await EncryptionHelper.init();
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      const String appSecret = String.fromEnvironment('APP_SECRET');
      
      // ✅ نأخذ نسخة من مفتاح التشفير (Base64) لإرساله للخيط الخلفي
      // لأن الخيط الخلفي لا يستطيع الوصول للـ SecureStorage مباشرة
      final String keyBase64 = EncryptionHelper.key.base64;

      if (userId == null) throw Exception("User auth missing");

      // 1. تجهيز الروابط (يتم بسرعة على الخيط الرئيسي)
      String? finalVideoUrl = downloadUrl;
      String? finalAudioUrl = audioUrl;

      if (finalVideoUrl == null) {
        if (isPdf) {
           finalVideoUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
        } else {
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

      if (!isPdf && (duration.isEmpty || duration == "--:--")) {
        String ext = _extractDurationFromUrl(finalVideoUrl);
        if (ext.isNotEmpty) duration = ext;
      }

      // 2. تجهيز المسارات
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

      // 3. ✅ تشغيل الـ Isolate للقيام بالمهمة الثقيلة
      final receivePort = ReceivePort();
      
      final isolate = await Isolate.spawn(
        _downloadIsolateEntryPoint,
        _DownloadTask(
          sendPort: receivePort.sendPort,
          keyBase64: keyBase64,
          videoUrl: finalVideoUrl,
          videoSavePath: videoSavePath,
          audioUrl: finalAudioUrl,
          audioSavePath: audioSavePath,
          headers: {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret},
          isPdf: isPdf,
        ),
      );

      _activeIsolates[lessonId] = isolate;

      // 4. الاستماع لرسائل التقدم أو الخطأ من الخلفية
      await for (final message in receivePort) {
        if (message is double) {
          // تحديث واجهة المستخدم والإشعارات
          var prog = Map<String, double>.from(downloadingProgress.value);
          prog[lessonId] = message;
          downloadingProgress.value = prog; 
          onProgress(message);

          int percent = (message * 100).toInt();
          // تحديث الإشعار كل 2% لتقليل الضغط
          if (percent % 2 == 0) { 
            notifService.showProgressNotification(
              id: notificationId, 
              title: isPdf ? "Downloading PDF..." : "Downloading: $videoTitle",
              body: "$percent%",
              progress: percent, maxProgress: 100,
            );
          }
        } else if (message == "DONE") {
          // تم التحميل بنجاح
          receivePort.close();
          _activeIsolates.remove(lessonId);
          break;
        } else if (message.toString().startsWith("ERROR")) {
          // حدث خطأ في الخلفية
          receivePort.close();
          _activeIsolates.remove(lessonId);
          throw Exception(message.toString().replaceFirst("ERROR: ", ""));
        }
      }

      // 5. الحفظ في قاعدة البيانات بعد النجاح
      int totalSizeBytes = await File(videoSavePath).length();
      if (audioSavePath != null && await File(audioSavePath).exists()) {
        totalSizeBytes += await File(audioSavePath).length();
      }

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
        'size': totalSizeBytes,
      });

      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: true,
      );

      onComplete();

    } catch (e, stack) {
      await notifService.cancelNotification(notificationId);
      
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed');
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: false,
      );
      onError("Download failed. Please try again.");
      
      // تنظيف في حالة الخطأ
      _activeIsolates[lessonId]?.kill(priority: Isolate.immediate);
      _activeIsolates.remove(lessonId);
      
      // حذف الملفات المعطوبة
      try {
        // (يمكن إعادة بناء المسار للحذف هنا إذا لزم الأمر)
      } catch (_) {}

    } finally {
      _activeDownloads.remove(lessonId);
      activeTitles.remove(lessonId);
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
      
      if (_activeDownloads.isEmpty) {
         _stopBackgroundService();
      }
    }
  }
}

// -----------------------------------------------------------------------------
// ⚠️ منطقة الكود المعزول (Background Isolate Logic)
// هذا الكود يعمل في عملية منفصلة ولا يؤثر على واجهة المستخدم
// -----------------------------------------------------------------------------

class _DownloadTask {
  final SendPort sendPort;
  final String keyBase64;
  final String videoUrl;
  final String videoSavePath;
  final String? audioUrl;
  final String? audioSavePath;
  final Map<String, dynamic> headers;
  final bool isPdf;

  _DownloadTask({
    required this.sendPort,
    required this.keyBase64,
    required this.videoUrl,
    required this.videoSavePath,
    this.audioUrl,
    this.audioSavePath,
    required this.headers,
    required this.isPdf,
  });
}

// نقطة البداية للخيط الجديد
void _downloadIsolateEntryPoint(_DownloadTask task) async {
  try {
    // 1. إعادة بناء التشفير في الخلفية
    final key = encrypt.Key.fromBase64(task.keyBase64);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    
    final dio = Dio();

    // دالة مساعدة للتحميل والتقسيم والتشفير (Chunked Stream Download)
    Future<void> downloadAndEncrypt(String url, String path, {Function(double)? onProg}) async {
      final saveFile = File(path);
      final sink = await saveFile.open(mode: FileMode.write);
      
      try {
        final response = await dio.get(
          url,
          options: Options(
            responseType: ResponseType.stream, // استلام كـ Stream لتوفير الرام
            headers: task.headers,
            followRedirects: true,
          ),
        );

        int total = int.parse(response.headers.value(Headers.contentLengthHeader) ?? '-1');
        int received = 0;
        
        // مخزن مؤقت لتجميع البيانات (Buffer)
        List<int> buffer = [];
        // حجم الكتلة: 128KB (يجب أن يطابق ما يستخدمه البروكسي في فك التشفير)
        const int CHUNK_SIZE = 128 * 1024; 

        Stream<Uint8List> stream = response.data.stream;
        
        await for (final chunk in stream) {
          buffer.addAll(chunk);
          
          // كلما جمعنا 128KB، نقوم بتشفيرها وكتابتها فوراً
          while (buffer.length >= CHUNK_SIZE) {
            final block = buffer.sublist(0, CHUNK_SIZE);
            buffer.removeRange(0, CHUNK_SIZE);
            
            // التشفير (Heavy Operation)
            final iv = encrypt.IV.fromSecureRandom(12);
            final encrypted = encrypter.encryptBytes(block, iv: iv);
            
            // الكتابة: IV + Data + Tag
            // ملاحظة: Encrypter في GCM يدمج الـ Tag تلقائياً في encrypted.bytes عادةً
            // لكن هنا سنكتب IV ثم البيانات المشفرة
            final result = BytesBuilder();
            result.add(iv.bytes);
            result.add(encrypted.bytes); // يشمل الـ Auth Tag
            
            await sink.writeFrom(result.toBytes());
          }
          
          received += chunk.length;
          if (total != -1 && onProg != null) {
             onProg(received / total);
          }
        }
        
        // تشفير ما تبقى في البفر (الكتلة الأخيرة)
        if (buffer.isNotEmpty) {
            final iv = encrypt.IV.fromSecureRandom(12);
            final encrypted = encrypter.encryptBytes(buffer, iv: iv);
            final result = BytesBuilder();
            result.add(iv.bytes);
            result.add(encrypted.bytes);
            await sink.writeFrom(result.toBytes());
        }

      } finally {
        await sink.close();
      }
    }

    // 2. بدء العمليات
    if (task.isPdf) {
      await downloadAndEncrypt(task.videoUrl, task.videoSavePath, onProg: (p) {
        task.sendPort.send(p);
      });
    } else {
      // تحميل الفيديو والصوت (إن وجد)
      double vidProg = 0.0;
      double audProg = 0.0;

      // دالة لتجميع التقدم وإرساله للخيط الرئيسي
      void updateProgress() {
        double total = (task.audioUrl != null) 
            ? (vidProg * 0.80) + (audProg * 0.20) // الفيديو يمثل 80% من التقدم
            : vidProg;
        task.sendPort.send(total);
      }

      final List<Future> downloads = [];
      
      downloads.add(downloadAndEncrypt(task.videoUrl, task.videoSavePath, onProg: (p) {
        vidProg = p;
        updateProgress();
      }));

      if (task.audioUrl != null && task.audioSavePath != null) {
        downloads.add(downloadAndEncrypt(task.audioUrl!, task.audioSavePath!, onProg: (p) {
          audProg = p;
          updateProgress();
        }));
      }

      await Future.wait(downloads);
    }

    // 3. إبلاغ النجاح
    task.sendPort.send("DONE");

  } catch (e) {
    task.sendPort.send("ERROR: $e");
  }
}
