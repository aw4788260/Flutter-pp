import 'dart:io';
import 'dart:async';
import 'dart:math'; // لاستخدام min
import 'dart:typed_data'; // للتعامل مع Uint8List
import 'package:flutter/foundation.dart'; // للـ ValueNotifier
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/encryption_helper.dart';

class DownloadManager {
  static final Dio _dio = Dio();
  static final Set<String> _activeDownloads = {};

  // متغير عام لمراقبة التقدم (Key: LessonId, Value: Percentage 0.0-1.0)
  static final ValueNotifier<Map<String, double>> downloadingProgress = ValueNotifier({});

  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  bool isFileDownloading(String id) {
    return _activeDownloads.contains(id);
  }

  bool isFileDownloaded(String id) {
    if (!Hive.isBoxOpen('downloads_box')) return false;
    return Hive.box('downloads_box').containsKey(id);
  }

  /// دالة بدء عملية التحميل
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
  }) async {
    // تسجيل بداية العملية
    FirebaseCrashlytics.instance.log("⬇️ Start Download: $videoTitle ($lessonId) - PDF: $isPdf");
    
    _activeDownloads.add(lessonId);
    
    // تهيئة شريط التقدم بـ 0 عند البدء
    var currentProgress = Map<String, double>.from(downloadingProgress.value);
    currentProgress[lessonId] = 0.0;
    downloadingProgress.value = currentProgress;

    try {
      // التأكد من تهيئة التشفير قبل البدء بأي شيء
      await EncryptionHelper.init();

      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      if (userId == null || deviceId == null) {
        throw Exception("User authentication missing");
      }

      const String appSecret = String.fromEnvironment(
        'APP_SECRET',
        defaultValue: 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only',
      );

      String? finalUrl = downloadUrl;

      // 1. جلب الرابط تلقائياً إذا لم يتم توفيره
      if (finalUrl == null) {
        final endpoint = isPdf ? '/api/secure/get-pdf' : '/api/secure/get-video-id';
        final queryParam = isPdf ? {'pdfId': lessonId} : {'lessonId': lessonId};

        FirebaseCrashlytics.instance.log("🔍 Fetching URL from: $endpoint");

        final res = await _dio.get(
          '$_baseUrl$endpoint',
          queryParameters: queryParam,
          options: Options(
            headers: {
              'x-user-id': userId,
              'x-device-id': deviceId,
              'x-app-secret': appSecret,
            },
            validateStatus: (status) => status! < 500,
          ),
        );

        if (res.statusCode != 200) {
          throw Exception(res.data['message'] ?? "Failed to get content info (${res.statusCode})");
        }

        final data = res.data;
        
        if (isPdf) {
           finalUrl = data['url'];
           if (finalUrl == null) {
             finalUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
           }
        } else {
          if (data['youtube_video_id'] != null && (data['availableQualities'] == null || (data['availableQualities'] as List).isEmpty)) {
             throw Exception("YouTube videos cannot be downloaded offline.");
          }

          if (data['availableQualities'] != null) {
            List qualities = data['availableQualities'];
            var q720 = qualities.firstWhere((q) => q['quality'] == 720, orElse: () => null);
            if (q720 != null) finalUrl = q720['url'];
            else if (qualities.isNotEmpty) finalUrl = qualities.first['url'];
          }
          if (finalUrl == null && data['url'] != null) finalUrl = data['url'];
        }
      }

      if (finalUrl == null) {
        throw Exception("No valid download link found");
      }

      FirebaseCrashlytics.instance.log("🔗 Resolved URL: $finalUrl");

      // 2. تجهيز المسارات
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
      };

      // 3. التحميل (إلى ملف مؤقت غير مشفر)
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));

      if (isHls) {
        await _downloadAndMergeHls(finalUrl!, tempPath, internalOnProgress);
      } else {
        Options downloadOptions = Options();
        if (finalUrl.contains(_baseUrl)) {
           downloadOptions = Options(headers: {
              'x-user-id': userId,
              'x-device-id': deviceId,
              'x-app-secret': appSecret,
           });
        } 

        await _dio.download(
          finalUrl,
          tempPath,
          options: downloadOptions,
          onReceiveProgress: (received, total) {
            if (total != -1) internalOnProgress(received / total);
          },
        );
      }

      FirebaseCrashlytics.instance.log("✅ Download Finished. Starting Chunked GCM Encryption...");

      // 4. التشفير (Chunked AES-GCM) ✅✅✅ التحديث الجديد
      if (await tempFile.exists()) {
        final fileSize = await tempFile.length();
        int minSize = isPdf ? 100 : 1024 * 10; 
        
        if (fileSize < minSize) { 
          await tempFile.delete();
          throw Exception("Download failed: File is too small ($fileSize bytes)");
        }

        // استخدام دالة التشفير الجديدة
        await _encryptFileStream(tempFile, File(savePath));
        
        await tempFile.delete(); 
        FirebaseCrashlytics.instance.log("🔒 Encryption Success: $savePath");

      } else {
        throw Exception("Temp file not found after download process");
      }

      // 5. حفظ البيانات في Hive
      var downloadsBox = await Hive.openBox('downloads_box');
      await downloadsBox.put(lessonId, {
        'id': lessonId,
        'title': videoTitle,
        'path': savePath,
        'course': courseName,
        'subject': subjectName,
        'chapter': chapterName,
        'type': isPdf ? 'pdf' : 'video',
        'date': DateTime.now().toIso8601String(),
        'size': File(savePath).lengthSync(),
      });

      onComplete();

    } catch (e, stack) {
      if (e is DioException) {
          FirebaseCrashlytics.instance.log("🌐 Dio Error URL: ${e.requestOptions.uri}");
          FirebaseCrashlytics.instance.log("🌐 Dio Error Status: ${e.response?.statusCode}");
      }
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Process Failed: $lessonId');
      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;
    }
  }

  /// ✅ دالة التشفير الجديدة: تعتمد على Chunked AES-GCM
  /// تقوم بتقسيم الملف إلى كتل، وتشفير كل كتلة بشكل مستقل مع IV خاص بها
  Future<void> _encryptFileStream(File inputFile, File outputFile) async {
    RandomAccessFile? rafRead;
    RandomAccessFile? rafWrite;

    try {
      // التأكد من تهيئة المفاتيح
      await EncryptionHelper.init();

      rafRead = await inputFile.open(mode: FileMode.read);
      rafWrite = await outputFile.open(mode: FileMode.write);
      
      final int fileLength = await inputFile.length();
      int bytesRead = 0;
      
      // استخدام حجم الكتلة المحدد في Helper (64KB)
      const int chunkSize = EncryptionHelper.CHUNK_SIZE;
      
      FirebaseCrashlytics.instance.log("🔒 Encrypting file: ${inputFile.path} -> ${outputFile.path} (Size: $fileLength)");

      while (bytesRead < fileLength) {
        // تحديد كمية القراءة (الكتلة الأخيرة قد تكون أصغر)
        int toRead = min(chunkSize, fileLength - bytesRead);
        
        // قراءة البيانات الصافية
        Uint8List chunk = await rafRead.read(toRead);
        if (chunk.isEmpty) break;

        // تشفير الكتلة (تقوم الدالة بتوليد IV ودمجه مع الناتج)
        try {
          Uint8List encryptedChunk = EncryptionHelper.encryptBlock(chunk);
          
          // كتابة الكتلة المشفرة
          await rafWrite.writeFrom(encryptedChunk);
        } catch (e, stack) {
          FirebaseCrashlytics.instance.recordError(
            e, 
            stack, 
            reason: 'Block Encryption Failed at pos: $bytesRead'
          );
          throw e;
        }
        
        bytesRead += chunk.length;
      }
      
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Full Encryption Loop Failed');
      throw Exception("Encryption Loop Failed: $e");
    } finally {
      await rafRead?.close();
      await rafWrite?.flush();
      await rafWrite?.close();
    }
  }

  // 🔥 دالة دمج ملفات HLS
  Future<void> _downloadAndMergeHls(String m3u8Url, String outputPath, Function(double) onProgress) async {
    try {
      FirebaseCrashlytics.instance.log("🔄 Starting HLS Merge for: $m3u8Url");
      
      final response = await _dio.get(m3u8Url);
      final content = response.data.toString();
      final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1);

      List<String> tsUrls = [];
      final lines = content.split('\n');
      for (var line in lines) {
        line = line.trim();
        if (line.isNotEmpty && !line.startsWith('#')) {
          if (line.startsWith('http')) {
            tsUrls.add(line);
          } else {
            tsUrls.add(baseUrl + line);
          }
        }
      }

      if (tsUrls.isEmpty) throw Exception("No TS segments found in M3U8");

      final outputFile = File(outputPath);
      final sink = outputFile.openWrite(mode: FileMode.writeOnlyAppend);

      int totalSegments = tsUrls.length;
      int downloadedSegments = 0;

      for (String url in tsUrls) {
        final rs = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        
        if (rs.data != null) {
          sink.add(rs.data!);
        }

        downloadedSegments++;
        onProgress(downloadedSegments / totalSegments);
      }

      await sink.flush();
      await sink.close();
      FirebaseCrashlytics.instance.log("✅ HLS Merge Complete");

    } catch (e) {
      throw Exception("Manual HLS Merge Failed: $e");
    }
  }
}
