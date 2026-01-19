import 'dart:io';
import 'dart:async';
import 'dart:isolate'; 
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/widgets.dart'; 
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt; 
import 'package:device_info_plus/device_info_plus.dart'; 

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

  // ✅ تخزين الـ Isolates للتحكم فيها (إلغاء/قتل)
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

  // ✅ دالة الذكاء: تحديد الحجم المناسب للجهاز
  Future<int> _getOptimalChunkSize() async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        // أندرويد 9 (API 28) وما قبل يعتبر قديماً -> 32KB
        if (androidInfo.version.sdkInt <= 28) {
          return 32 * 1024; 
        }
      } catch (e) {
        return 32 * 1024; // احتياطي للأمان
      }
    }
    // للأجهزة الحديثة -> 64KB (توازن ممتاز بين السرعة والأداء)
    return 128 * 1024;
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
    // قتل الـ Isolate يوقف التحميل والتشفير فوراً دون انتظار
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
  // 🚀 Start Download Logic (Main Thread Handler)
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
      await EncryptionHelper.init();
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      const String appSecret = String.fromEnvironment('APP_SECRET');
      
      final String keyBase64 = EncryptionHelper.key.base64;

      if (userId == null) throw Exception("User auth missing");

      // 1. ⚡ تحديد حجم الشنك المناسب
      final int chunkSize = await _getOptimalChunkSize();
      // إضافة العلامة لاسم الملف ليتعرف عليها البروكسي لاحقاً
      final String chunkTag = (chunkSize == 32 * 1024) ? ".c32" : ".c128";

      // 2. تجهيز الروابط
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

      // 3. تجهيز المسارات (مع إضافة العلامة لاسم الملف)
      final appDir = await getApplicationDocumentsDirectory();
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      // اسم الملف يحتوي على العلامة: vid_123.c32.enc
      final String videoFileName = isPdf 
          ? "$lessonId$chunkTag.pdf.enc" 
          : "vid_${lessonId}_$quality$chunkTag.enc";
          
      final String videoSavePath = '${dir.path}/$videoFileName';
      
      String? audioSavePath;
      if (finalAudioUrl != null) {
        audioSavePath = '${dir.path}/aud_${lessonId}_hq$chunkTag.enc';
      }

      // 4. 🔥 بدء الـ Isolate (العزل)
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
          chunkSize: chunkSize, // ✅ تمرير الحجم المختار للخلفية
        ),
      );

      _activeIsolates[lessonId] = isolate;

      // 5. الاستماع للنتائج من الخلفية
      await for (final message in receivePort) {
        if (message is double) {
          var prog = Map<String, double>.from(downloadingProgress.value);
          prog[lessonId] = message;
          downloadingProgress.value = prog; 
          onProgress(message);

          int percent = (message * 100).toInt();
          // تحديث الإشعار كل 2% فقط لتخفيف الضغط
          if (percent % 2 == 0) { 
            notifService.showProgressNotification(
              id: notificationId, 
              title: isPdf ? "Downloading PDF..." : "Downloading: $videoTitle",
              body: "$percent%",
              progress: percent, maxProgress: 100,
            );
          }
        } else if (message == "DONE") {
          receivePort.close();
          _activeIsolates.remove(lessonId);
          break;
        } else if (message.toString().startsWith("ERROR")) {
          receivePort.close();
          _activeIsolates.remove(lessonId);
          throw Exception(message.toString().replaceFirst("ERROR: ", ""));
        }
      }

      // 6. الحفظ في قاعدة البيانات (Hive) بعد النجاح
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
        'chunkSize': chunkSize, // تخزين الحجم كمرجع (اختياري)
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
      
      _activeIsolates[lessonId]?.kill(priority: Isolate.immediate);
      _activeIsolates.remove(lessonId);
      
      try {
         // حذف الملفات المعطوبة
         final file = File('$dir/${isPdf ? "$lessonId.pdf.enc" : "vid_${lessonId}_$quality.enc"}');
         if (await file.exists()) await file.delete();
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
// ⚠️ كود الخلفية (The Heavy Lifter)
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
  final int chunkSize; 

  _DownloadTask({
    required this.sendPort,
    required this.keyBase64,
    required this.videoUrl,
    required this.videoSavePath,
    this.audioUrl,
    this.audioSavePath,
    required this.headers,
    required this.isPdf,
    required this.chunkSize,
  });
}

void _downloadIsolateEntryPoint(_DownloadTask task) async {
  try {
    final key = encrypt.Key.fromBase64(task.keyBase64);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final dio = Dio();

    // دالة التحميل المباشر المتزامنة (Fast Logic)
    Future<void> downloadAndEncrypt(String url, String path, {Function(double)? onProg}) async {
      final saveFile = File(path);
      final sink = await saveFile.open(mode: FileMode.write);
      
      try {
        final response = await dio.get(
          url,
          options: Options(
            responseType: ResponseType.stream, 
            headers: task.headers,
            followRedirects: true,
          ),
        );

        int total = int.parse(response.headers.value(Headers.contentLengthHeader) ?? '-1');
        int received = 0;
        
        List<int> buffer = [];
        final int CHUNK_SIZE = task.chunkSize; 

        Stream<Uint8List> stream = response.data.stream;
        int lastPercent = 0;

        await for (final chunk in stream) {
          buffer.addAll(chunk);
          
          // 🔥 التشفير المتزامن السريع داخل الـ Stream
          // هذا اللوب يضمن أننا لا نراكم البيانات في الرام بل نعالجها فوراً
          while (buffer.length >= CHUNK_SIZE) {
            final block = buffer.sublist(0, CHUNK_SIZE);
            buffer.removeRange(0, CHUNK_SIZE);
            
            final iv = encrypt.IV.fromSecureRandom(12);
            final encrypted = encrypter.encryptBytes(block, iv: iv);
            
            final result = BytesBuilder();
            result.add(iv.bytes);
            result.add(encrypted.bytes); // GCM includes Tag inside bytes usually
            
            await sink.writeFrom(result.toBytes());
          }
          
          received += chunk.length;
          
          // تحديث التقدم (Throttled) لعدم إبطاء الـ Isolate بكثرة الرسائل
          if (total != -1 && onProg != null) {
             int currentPercent = (received * 100) ~/ total;
             // إرسال التحديث فقط إذا زادت النسبة 1%
             if (currentPercent > lastPercent) {
                lastPercent = currentPercent;
                onProg(received / total);
             }
          }
        }
        
        // تشفير ما تبقى في البفر
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

    if (task.isPdf) {
      await downloadAndEncrypt(task.videoUrl, task.videoSavePath, onProg: (p) {
        task.sendPort.send(p);
      });
    } else {
      double vidProg = 0.0;
      double audProg = 0.0;

      void updateProgress() {
        double total = (task.audioUrl != null) 
            ? (vidProg * 0.80) + (audProg * 0.20)
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

    task.sendPort.send("DONE");

  } catch (e) {
    task.sendPort.send("ERROR: $e");
  }
}
