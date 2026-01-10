import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// تأكد من أن المكتبة مضافة في pubspec.yaml باسم: ffmpeg_kit_flutter_https_gpl
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
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

  /// دالة بدء عملية التحميل (تدعم الفيديو و PDF)
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
    bool isPdf = false, // معامل جديد لتحديد نوع الملف
  }) async {
    _activeDownloads.add(lessonId);

    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      if (userId == null || deviceId == null) {
        throw Exception("User authentication missing");
      }

      // استخدام قيمة افتراضية للـ Secret لضمان العمل
      const String appSecret = String.fromEnvironment(
        'APP_SECRET', 
        defaultValue: 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only' 
      );

      String? finalUrl = downloadUrl;

      // 1. جلب الرابط تلقائياً إذا لم يتم توفيره
      if (finalUrl == null) {
        // تحديد نقطة النهاية (Endpoint) بناءً على نوع الملف
        final endpoint = isPdf ? '/api/secure/get-pdf' : '/api/secure/get-video-id';
        // المعامل المطلوب (pdfId للـ PDF و lessonId للفيديو)
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
          // في حالة PDF، الرابط قد يكون مباشراً أو يحتاج لبناء
          // نفترض هنا أن الـ API يعيد الرابط في حقل 'url' أو يتم استنتاجه
          // هذا يعتمد على هيكل الرد الخاص بك للـ PDF.
          // إذا كان الـ API يعيد الملف مباشرة (Binary)، سنحتاج لمنطق مختلف.
          // هنا نفترض أنه يعيد رابطاً مثل الفيديو.
           finalUrl = data['url'];
           // إذا كان الـ API يعيد الملف binary مباشرة، يجب استخدام dio.download مع الرابط أعلاه
           if (finalUrl == null) {
             // fallback: بناء رابط التحميل المباشر
             finalUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
           }
        } else {
          // منطق الفيديو (كما هو سابقاً)
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
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final tempPath = '${dir.path}/$lessonId.temp';
      final savePath = '${dir.path}/$lessonId.enc';

      File tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();

      // 3. التحميل (حسب النوع)
      
      // ✅ دعم HLS للفيديو فقط
      bool isHls = !isPdf && (finalUrl.contains('.m3u8') || finalUrl.contains('.m3u'));

      if (isHls) {
        // --- تحميل الفيديو باستخدام FFmpeg ---
        String userAgent = 'Mozilla/5.0 (Linux; Android 10; Mobile; rv:100.0) Gecko/100.0 Firefox/100.0';
        final command = '-y -user_agent "$userAgent" -i "$finalUrl" -c copy -bsf:a aac_adtstoasc -f mp4 "$tempPath"';
        
        onProgress(0.1); 
        
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (!ReturnCode.isSuccess(returnCode)) {
           final failStackTrace = await session.getFailStackTrace();
           final logs = await session.getLogs();
           String logMsg = logs.map((l) => l.getMessage()).join("\n");
           FirebaseCrashlytics.instance.log("FFmpeg Output: $logMsg");
           throw Exception("FFmpeg failed: $failStackTrace");
        }
        onProgress(0.9);
      } else {
        // --- تحميل مباشر (MP4 أو PDF) ---
        Options downloadOptions = Options();
        // إضافة الهيدرز إذا كان الرابط من السيرفر الخاص بنا
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
            if (total != -1) {
              onProgress(received / total);
            }
          },
        );
      }

      // 4. التشفير والحفظ
      if (await tempFile.exists()) {
        final fileSize = await tempFile.length();
        
        // ✅ تعديل شرط الحجم: ملفات PDF قد تكون صغيرة (مثلاً 50KB)، الفيديو لا يقل عن 500KB غالباً
        int minSize = isPdf ? 1024 * 10 : 1024 * 500; // 10KB للـ PDF و 500KB للفيديو
        
        if (fileSize < minSize) { 
          await tempFile.delete();
          throw Exception("Download failed: File corrupted or too small ($fileSize bytes)");
        }

        final bytes = await tempFile.readAsBytes();
        
        final encrypted = EncryptionHelper.encrypter.encryptBytes(
          bytes, 
          iv: EncryptionHelper.iv
        );
        
        final finalFile = File(savePath);
        await finalFile.writeAsBytes(encrypted.bytes);
        await tempFile.delete();
      } else {
        throw Exception("Download failed: Temp file not created");
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
        'type': isPdf ? 'pdf' : 'video', // حفظ نوع الملف
        'date': DateTime.now().toIso8601String(),
        'size': File(savePath).lengthSync(),
      });

      onComplete();

    } catch (e, stack) {
      // تسجيل الأخطاء الخام (Raw Logs)
      if (e is DioException) {
          FirebaseCrashlytics.instance.log("🌐 URL: ${e.requestOptions.uri}");
          if(e.response != null) {
            FirebaseCrashlytics.instance.log("🔢 Status: ${e.response?.statusCode}");
            FirebaseCrashlytics.instance.log("📄 Response: ${e.response?.data}");
          }
      }
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed: $lessonId (PDF: $isPdf)');
      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
    }
  }
}
