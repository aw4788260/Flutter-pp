import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// ✅ التعديل: الاستيراد من المكتبة الجديدة والمحدثة
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
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

  /// دالة بدء عملية التحميل (تدعم الفيديو HLS/MP4 و ملفات PDF)
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
    bool isPdf = false, // تحديد نوع الملف
  }) async {
    _activeDownloads.add(lessonId);

    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      if (userId == null || deviceId == null) {
        throw Exception("User authentication missing");
      }

      // الحصول على السر من متغيرات البيئة مع قيمة افتراضية للأمان
      const String appSecret = String.fromEnvironment(
        'APP_SECRET', 
        defaultValue: 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only' 
      );

      String? finalUrl = downloadUrl;

      // 1. جلب الرابط تلقائياً إذا لم يتم توفيره بناءً على نوع المحتوى
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

      // 2. تجهيز المسارات (دعم العربية وتنظيف الرموز)
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

      // 3. التحميل (HLS للفيديو فقط، Dio للـ MP4 و PDF)
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));

      if (isHls) {
        // --- تحميل وتحويل HLS باستخدام FFmpeg ---
        String userAgent = 'Mozilla/5.0 (Linux; Android 10; Mobile; rv:100.0) Gecko/100.0 Firefox/100.0';
        // إجبار الصيغة على mp4 لضمان عمل التشفير لاحقاً
        final command = '-y -user_agent "$userAgent" -i "$finalUrl" -c copy -bsf:a aac_adtstoasc -f mp4 "$tempPath"';
        
        onProgress(0.1); 
        
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (!ReturnCode.isSuccess(returnCode)) {
           final failStackTrace = await session.getFailStackTrace();
           final logs = await session.getLogs();
           String logMsg = logs.map((l) => l.getMessage()).join("\n");
           FirebaseCrashlytics.instance.log("FFmpeg Error: $logMsg");
           throw Exception("FFmpeg failed to process video: $failStackTrace");
        }
        onProgress(0.9);
      } else {
        // --- تحميل مباشر باستخدام Dio (MP4 أو PDF) ---
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
        
        // حد أدنى مختلف: 10KB للـ PDF و 500KB للفيديو
        int minSize = isPdf ? 1024 * 10 : 1024 * 500; 
        
        if (fileSize < minSize) { 
          await tempFile.delete();
          throw Exception("Download failed: File is too small or corrupted ($fileSize bytes)");
        }

        final bytes = await tempFile.readAsBytes();
        final encrypted = EncryptionHelper.encrypter.encryptBytes(bytes, iv: EncryptionHelper.iv);
        
        final finalFile = File(savePath);
        await finalFile.writeAsBytes(encrypted.bytes);
        await tempFile.delete(); // حذف الملف المؤقت غير المشفر
      } else {
        throw Exception("Temp file not found after download process");
      }

      // 5. حفظ البيانات في Hive للاستخدام أوفلاين
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
          if(e.response != null) {
            FirebaseCrashlytics.instance.log("🔢 Status: ${e.response?.statusCode}");
            FirebaseCrashlytics.instance.log("📄 Body: ${e.response?.data}");
          }
      }
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed: $lessonId (Is PDF: $isPdf)');
      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
    }
  }
}
