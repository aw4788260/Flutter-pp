import 'dart:io';
import 'dart:async'; // للإدارة المتزامنة
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// ❌ تم حذف استيراد FFmpeg نهائياً
import '../utils/encryption_helper.dart';

class DownloadManager {
  static final Dio _dio = Dio();
  static final Set<String> _activeDownloads = {};

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
    _activeDownloads.add(lessonId);

    try {
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

      // 1. جلب الرابط تلقائياً
      if (finalUrl == null) {
        final endpoint = isPdf ? '/api/secure/get-pdf' : '/api/secure/get-video-id';
        final queryParam = isPdf ? {'pdfId': lessonId} : {'lessonId': lessonId};

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

      // 2. تجهيز المسارات
      final appDir = await getApplicationDocumentsDirectory();
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      final tempPath = '${dir.path}/$lessonId.temp'; // الملف المؤقت النهائي
      final savePath = '${dir.path}/$lessonId.enc';  // الملف المشفر النهائي

      File tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();

      // 3. منطق التحميل الجديد (بدون FFmpeg)
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));

      if (isHls) {
        // ✅ استخدام دالة الدمج اليدوي بدلاً من FFmpeg
        await _downloadAndMergeHls(finalUrl!, tempPath, onProgress);
      } else {
        // التحميل المباشر (MP4/PDF)
        Options downloadOptions = Options();
        if (finalUrl.contains(_baseUrl) || isPdf) {
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
            if (total != -1) onProgress(received / total);
          },
        );
      }

      // 4. التحقق من سلامة الملف وتشفيره
      if (await tempFile.exists()) {
        final fileSize = await tempFile.length();
        int minSize = isPdf ? 1024 * 10 : 1024 * 100; // تقليل الحد الأدنى قليلاً للتأكيد
        
        if (fileSize < minSize) { 
          await tempFile.delete();
          throw Exception("Download failed: File is too small or corrupted ($fileSize bytes)");
        }

        // قراءة الملف وتشفيره
        final bytes = await tempFile.readAsBytes();
        final encrypted = EncryptionHelper.encrypter.encryptBytes(bytes, iv: EncryptionHelper.iv);
        
        final finalFile = File(savePath);
        await finalFile.writeAsBytes(encrypted.bytes);
        await tempFile.delete(); // تنظيف الملف المؤقت
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
          FirebaseCrashlytics.instance.log("🌐 Dio URL: ${e.requestOptions.uri}");
      }
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed: $lessonId');
      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
    }
  }

  // 🔥🔥🔥 الدالة السحرية الجديدة لدمج الفيديو يدوياً 🔥🔥🔥
  Future<void> _downloadAndMergeHls(String m3u8Url, String outputPath, Function(double) onProgress) async {
    try {
      // 1. تحميل ملف القائمة (Playlist)
      final response = await _dio.get(m3u8Url);
      final content = response.data.toString();
      final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1);

      // 2. استخراج روابط ملفات الـ .ts
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

      // 3. تحميل الأجزاء ودمجها مباشرة
      final outputFile = File(outputPath);
      // فتح الملف في وضع "الإضافة" (Append)
      final sink = outputFile.openWrite(mode: FileMode.writeOnlyAppend);

      int totalSegments = tsUrls.length;
      int downloadedSegments = 0;

      for (String url in tsUrls) {
        // تحميل الجزء كـ Bytes
        final rs = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        
        if (rs.data != null) {
          // كتابة البايتات مباشرة في نهاية الملف المجمع
          sink.add(rs.data!);
        }

        downloadedSegments++;
        // تحديث النسبة المئوية
        onProgress(downloadedSegments / totalSegments);
      }

      // إغلاق الملف وحفظ التغييرات
      await sink.flush();
      await sink.close();

    } catch (e) {
      throw Exception("Manual HLS Merge Failed: $e");
    }
  }
}
