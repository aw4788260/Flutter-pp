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

  static final Dio _mainThreadDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  static final Set<String> _activeDownloads = {};
  final Map<String, String> activeTitles = {};
  
  static final Map<String, Isolate> _activeIsolates = {}; 
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
    
    debugPrint("🛑 Download Cancelled & Isolate Killed: $lessonId");
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
      
      try {
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
    _keepAliveTimer?.cancel();
    try { await NotificationService().cancelNotification(888); } catch (e) {}

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
       service.invoke('stopService');
    }
  }

  // ---------------------------------------------------------------------------
  // 🚀 Start Download Logic (Main Thread Controller)
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
    // ✅ تصحيح: تعريف المسارات هنا لتكون مرئية في try و catch
    final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
    final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
    final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');

    activeTitles[lessonId] = videoTitle;
    FirebaseCrashlytics.instance.log("⬇️ Download Started: $videoTitle (PDF: $isPdf)");
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

    ReceivePort receivePort = ReceivePort();

    try {
      await EncryptionHelper.init();
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');
      const String appSecret = String.fromEnvironment('APP_SECRET');

      if (userId == null) throw Exception("User auth missing");

      String? finalVideoUrl = downloadUrl;
      String? finalAudioUrl = audioUrl;

      if (finalVideoUrl == null) {
        if (isPdf) {
           finalVideoUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
        } else {
           final res = await _mainThreadDio.get(
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

      final appDir = await getApplicationDocumentsDirectory();
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      final String videoFileName = isPdf ? "$lessonId.pdf.enc" : "vid_${lessonId}_$quality.enc";
      final String videoSavePath = '${dir.path}/$videoFileName';
      
      String? audioSavePath;
      if (finalAudioUrl != null) {
        audioSavePath = '${dir.path}/aud_${lessonId}_hq.enc';
      }

      final isolateArgs = {
        'sendPort': receivePort.sendPort,
        'url': finalVideoUrl,
        'audioUrl': finalAudioUrl,
        'savePath': videoSavePath,
        'audioSavePath': audioSavePath,
        'headers': {'x-user-id': userId, 'x-device-id': deviceId, 'x-app-secret': appSecret},
        'isPdf': isPdf,
        'lessonId': lessonId
      };

      Isolate isolate = await Isolate.spawn(_isolateDownloadWorker, isolateArgs);
      _activeIsolates[lessonId] = isolate;

      await for (final message in receivePort) {
        if (message is double) {
          var prog = Map<String, double>.from(downloadingProgress.value);
          prog[lessonId] = message;
          downloadingProgress.value = prog;
          onProgress(message);

          int percent = (message * 100).toInt();
          if (percent % 2 == 0) { 
            notifService.showProgressNotification(
              id: notificationId,
              title: isPdf ? "Downloading PDF..." : "Downloading: $videoTitle",
              body: "$percent%",
              progress: percent, maxProgress: 100,
            );
          }

        } else if (message == 'DONE') {
           break; 
        } else if (message is Map && message['error'] != null) {
           throw Exception(message['error']);
        }
      }

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

      FirebaseCrashlytics.instance.log("✅ Download Success: $videoTitle");
      onComplete();

    } catch (e, stack) {
      await notifService.cancelNotification(notificationId);
      
      bool isCancelled = !_activeDownloads.contains(lessonId); 
      
      if (!isCancelled) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed');
        await notifService.showCompletionNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
          title: videoTitle,
          isSuccess: false,
        );
        onError("Download failed. Please check internet.");
      }
      
      // Cleanup partial files
      try {
        final appDir = await getApplicationDocumentsDirectory();
        // ✅ الآن المتغيرات مرئية هنا
        final dirPath = '${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter';
        
        final videoFileName = isPdf ? "$lessonId.pdf.enc" : "vid_${lessonId}_$quality.enc";
        final audioFileName = 'aud_${lessonId}_hq.enc';
        
        final videoFile = File('$dirPath/$videoFileName');
        if (await videoFile.exists()) await videoFile.delete();
        
        final audioFile = File('$dirPath/$audioFileName');
        if (await audioFile.exists()) await audioFile.delete();

      } catch (cleanupError) {}

    } finally {
      _activeIsolates[lessonId]?.kill(priority: Isolate.immediate);
      _activeIsolates.remove(lessonId);
      _activeDownloads.remove(lessonId);
      activeTitles.remove(lessonId); 
      
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
      
      if (_activeDownloads.isEmpty) {
         _stopBackgroundService();
      }
      receivePort.close();
    }
  }

  // ---------------------------------------------------------------------------
  // 🧵 ISOLATE WORKER (Runs on Separate Thread)
  // ---------------------------------------------------------------------------
  
  static Future<void> _isolateDownloadWorker(Map<String, dynamic> args) async {
    final SendPort sendPort = args['sendPort'];
    final String url = args['url'];
    final String? audioUrl = args['audioUrl'];
    final String savePath = args['savePath'];
    final String? audioSavePath = args['audioSavePath'];
    final Map<String, dynamic> headers = args['headers'];
    final bool isPdf = args['isPdf'];

    final Dio dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ));

    await EncryptionHelper.init();
    final CancelToken localToken = CancelToken();

    try {
      if (isPdf) {
        await _downloadPdfWithEncryption(
          dio: dio,
          url: url,
          savePath: savePath,
          headers: headers,
          cancelToken: localToken,
          sendPort: sendPort,
        );
      } else {
        double vidProg = 0.0;
        double audProg = 0.0;

        void updateAggregatedProgress() {
          double total = (audioUrl != null) 
              ? (vidProg * 0.80) + (audProg * 0.20)
              : vidProg;
          sendPort.send(total);
        }

        final List<Future> tasks = [];
        
        tasks.add(_downloadFileSmartly(
          dio: dio,
          url: url,
          savePath: savePath,
          headers: headers,
          cancelToken: localToken,
          onProgress: (p) { vidProg = p; updateAggregatedProgress(); }
        ));

        if (audioUrl != null && audioSavePath != null) {
          tasks.add(_downloadFileSmartly(
            dio: dio,
            url: audioUrl,
            savePath: audioSavePath,
            headers: headers,
            cancelToken: localToken,
            onProgress: (p) { audProg = p; updateAggregatedProgress(); }
          ));
        }

        await Future.wait(tasks);
      }
      
      sendPort.send('DONE');

    } catch (e) {
      sendPort.send({'error': e.toString()});
    }
  }

  // ---------------------------------------------------------------------------
  // 📄 & 🎥 Static Download Helpers (Adapted for Isolate)
  // ---------------------------------------------------------------------------
  
  static Future<void> _downloadPdfWithEncryption({
    required Dio dio,
    required String url,
    required String savePath,
    required Map<String, dynamic> headers,
    required CancelToken cancelToken,
    required SendPort sendPort,
  }) async {
    final saveFile = File(savePath);
    final sink = await saveFile.open(mode: FileMode.write);

    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes, 
          headers: headers, 
          followRedirects: true
        ),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
           if (total != -1) sendPort.send(received / total);
        },
      );

      final bytes = response.data!;
      int offset = 0;

      while (offset < bytes.length) {
        int end = min(offset + EncryptionHelper.CHUNK_SIZE, bytes.length);
        final block = bytes.sublist(offset, end);
        
        final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(block));
        await sink.writeFrom(encrypted);
        
        offset += EncryptionHelper.CHUNK_SIZE;
      }

    } finally {
      await sink.close();
    }
  }

  static Future<void> _downloadFileSmartly({
    required Dio dio,
    required String url,
    required String savePath,
    required Map<String, dynamic> headers,
    required CancelToken cancelToken,
    required Function(double) onProgress,
  }) async {
    if (url.contains('.m3u8') || url.contains('.m3u')) {
      final saveFile = File(savePath);
      final sink = await saveFile.open(mode: FileMode.write);
      List<int> buffer = [];
      try {
         await _downloadHls(dio, url, sink, buffer, onProgress, cancelToken);
         if (buffer.isNotEmpty) {
           final enc = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
           await sink.writeFrom(enc);
         }
      } finally {
        await sink.close();
      }
      return;
    }

    int totalBytes = 0;
    try {
      final headRes = await dio.head(url, options: Options(headers: headers), cancelToken: cancelToken);
      totalBytes = int.parse(headRes.headers.value(Headers.contentLengthHeader) ?? '0');
    } catch (_) {}

    const int chunkSize = 1 * 1024 * 1024; 
    int downloadedBytes = 0;
    final saveFile = File(savePath);
    final sink = await saveFile.open(mode: FileMode.write);
    List<int> buffer = [];

    try {
      if (totalBytes <= 0) {
         await _downloadStreamBasic(dio, url, sink, buffer, onProgress, headers, cancelToken);
         if (buffer.isNotEmpty) {
           final enc = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
           await sink.writeFrom(enc);
         }
         return;
      }

      while (downloadedBytes < totalBytes) {
        int start = downloadedBytes;
        int end = min(start + chunkSize - 1, totalBytes - 1);
        
        bool chunkSuccess = false;
        int retries = 5; 

        while (retries > 0 && !chunkSuccess) {
          try {
            await _downloadChunkAndEncrypt(
              dio: dio, url: url, start: start, end: end, headers: headers, sink: sink, buffer: buffer,
              cancelToken: cancelToken,
            );
            chunkSuccess = true;
            downloadedBytes += (end - start + 1);
            onProgress(downloadedBytes / totalBytes);
          } catch (e) {
            retries--;
            if (retries == 0) throw Exception("Failed chunk");
            await Future.delayed(const Duration(seconds: 2)); 
          }
        }
      }

      if (buffer.isNotEmpty) {
        final enc = EncryptionHelper.encryptBlock(Uint8List.fromList(buffer));
        await sink.writeFrom(enc);
        buffer.clear();
      }

    } finally {
      await sink.close();
    }
  }

  static Future<void> _downloadChunkAndEncrypt({
    required Dio dio, required String url, required int start, required int end, required Map<String, dynamic> headers,
    required RandomAccessFile sink, required List<int> buffer, required CancelToken cancelToken,
  }) async {
    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...headers, 'Range': 'bytes=$start-$end'},
      ),
      cancelToken: cancelToken,
    );

    Stream<Uint8List> stream = response.data.stream;
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      while (buffer.length >= EncryptionHelper.CHUNK_SIZE) {
        final block = buffer.sublist(0, EncryptionHelper.CHUNK_SIZE);
        buffer.removeRange(0, EncryptionHelper.CHUNK_SIZE);
        final encrypted = EncryptionHelper.encryptBlock(Uint8List.fromList(block));
        await sink.writeFrom(encrypted);
      }
    }
  }

  static Future<void> _downloadStreamBasic(Dio dio, String url, RandomAccessFile sink, List<int> buffer, Function(double) onProgress, Map<String, dynamic> headers, CancelToken cancelToken) async {
    final response = await dio.get(url, options: Options(responseType: ResponseType.stream, headers: headers), cancelToken: cancelToken);
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

  static Future<void> _downloadHls(Dio dio, String m3u8Url, RandomAccessFile sink, List<int> buffer, Function(double) onProgress, CancelToken cancelToken) async {
      final response = await dio.get(m3u8Url, cancelToken: cancelToken);
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
            final rs = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 15)), cancelToken: cancelToken);
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
