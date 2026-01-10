import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart'; // ✅ إضافة المكتبة
import 'package:ffmpeg_kit_flutter/return_code.dart'; // ✅ إضافة المكتبة
import '../utils/encryption_helper.dart';

class DownloadManager {
  static final Dio _dio = Dio();
  static final Set<String> _activeDownloads = {};
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  bool isFileDownloading(String id) => _activeDownloads.contains(id);

  bool isFileDownloaded(String id) {
    if (!Hive.isBoxOpen('downloads_box')) return false;
    return Hive.box('downloads_box').containsKey(id);
  }

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
  }) async {
    _activeDownloads.add(lessonId);

    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      if (userId == null || deviceId == null) throw Exception("User auth missing");

      String? finalUrl = downloadUrl;

      // --- نفس منطق جلب الرابط (Parsing) الذي كتبته سابقاً ---
      if (finalUrl == null) {
        final res = await _dio.get(
          '$_baseUrl/api/secure/get-video-id',
          queryParameters: {'lessonId': lessonId},
          options: Options(
            headers: {
              'x-user-id': userId,
              'x-device-id': deviceId,
              'x-app-secret': const String.fromEnvironment('APP_SECRET'),
            },
          ),
        );

        if (res.statusCode != 200) throw Exception("API Error");
        final data = res.data;

        if (data['availableQualities'] != null) {
          List qualities = data['availableQualities'];
          // تفضيل 720p
          var q720 = qualities.firstWhere((q) => q['quality'] == 720, orElse: () => null);
          if (q720 != null) finalUrl = q720['url'];
          else if (qualities.isNotEmpty) finalUrl = qualities.first['url'];
        }
        if (finalUrl == null && data['url'] != null) finalUrl = data['url'];
      }

      if (finalUrl == null) throw Exception("No link found");

      // --- تجهيز المسارات ---
      final appDir = await getApplicationDocumentsDirectory();
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      final tempPath = '${dir.path}/$lessonId.temp'; // للملف الخام
      final savePath = '${dir.path}/$lessonId.enc';  // للملف المشفر النهائي
      
      // ✅✅ هنا التغيير الجوهري: التعامل مع m3u8 مقابل MP4 ✅✅
      
      File tempFile = File(tempPath);
      if (tempFile.exists()) await tempFile.delete(); // تنظيف القديم

      if (finalUrl.contains('.m3u8')) {
        // 🎥 حالة HLS: نستخدم FFmpeg للتحميل والتحويل لـ MP4
        // الأمر يقوم بتحميل الستريم ونسخه كملف واحد mp4
        final command = '-y -i "$finalUrl" -c copy -bsf:a aac_adtstoasc "$tempPath"';
        
        // ملاحظة: FFmpegKit لا يوفر progress دقيق بسهولة مثل Dio، لذا قد نرسل تحديثات وهمية أو نتركه indeterminate
        onProgress(0.1); 
        
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (!ReturnCode.isSuccess(returnCode)) {
           final failStackTrace = await session.getFailStackTrace();
           throw Exception("FFmpeg failed: $failStackTrace");
        }
        onProgress(0.9); // اكتمل التحميل تقريباً
        
      } else {
        // 📁 حالة ملف مباشر (MP4): نستخدم Dio كما هو
        await _dio.download(
          finalUrl,
          tempPath,
          onReceiveProgress: (received, total) {
            if (total != -1) onProgress(received / total);
          },
        );
      }

      // --- التشفير والحفظ (مشترك للكل) ---
      if (await tempFile.exists()) {
        final fileSize = await tempFile.length();
        if (fileSize < 1024 * 100) { // فحص الحجم لتجنب ملفات الخطأ
             throw Exception("File too small ($fileSize bytes). Download likely failed.");
        }

        final bytes = await tempFile.readAsBytes();
        final encrypted = EncryptionHelper.encrypter.encryptBytes(bytes, iv: EncryptionHelper.iv);
        
        final finalFile = File(savePath);
        await finalFile.writeAsBytes(encrypted.bytes);
        
        await tempFile.delete(); // حذف الملف غير المشفر
      } else {
        throw Exception("Temp file missing after download");
      }

      // 7. حفظ البيانات في Hive
      var downloadsBox = await Hive.openBox('downloads_box');
      await downloadsBox.put(lessonId, {
        'id': lessonId,
        'title': videoTitle,
        'path': savePath,
        'course': courseName,
        'subject': subjectName,
        'chapter': chapterName,
        'date': DateTime.now().toIso8601String(),
        'size': File(savePath).lengthSync(),
      });

      onComplete();

    } catch (e, stack) {
      if (e is DioException) {
          FirebaseCrashlytics.instance.log("🌐 URL: ${e.requestOptions.uri}");
          FirebaseCrashlytics.instance.log("🔢 Status: ${e.response?.statusCode}");
      }
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed: $lessonId');
      onError(e.toString());
    } finally {
      _activeDownloads.remove(lessonId);
    }
  }
}
