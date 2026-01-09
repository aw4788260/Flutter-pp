import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/encryption_helper.dart'; // تأكد أن ملف التشفير موجود

class DownloadManager {
  static final Dio _dio = Dio();
  // تأكد أن هذا الرابط مطابق لرابط الباك اند الخاص بك
  final String _baseUrl = 'https://courses.aw478260.dpdns.org'; 

  /// دالة بدء عملية التحميل
  Future<void> startDownload({
    required String lessonId,
    required String videoTitle,
    required String courseName,
    required String subjectName,
    required String chapterName,
    required Function(double) onProgress,
    required Function() onComplete,
    required Function(String) onError,
  }) async {
    try {
      // 1. تجهيز بيانات المصادقة
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      if (userId == null || deviceId == null) {
        throw Exception("User authentication missing");
      }

      // 2. الاتصال بالـ API لجلب رابط الفيديو
      // نستخدم نفس API المشغل لأنه يتصل بالبروكسي ويجلب الروابط الصالحة
      final res = await _dio.get(
        '$_baseUrl/api/secure/get-video-id',
        queryParameters: {'lessonId': lessonId},
        options: Options(
    headers: {
      'x-user-id': userId,
      'x-device-id': deviceId,
      'x-app-secret': const String.fromEnvironment('APP_SECRET'), // ✅ إضافة مباشرة
    },
    validateStatus: (status) => status! < 500,
  ),
      );

      if (res.statusCode != 200) {
        throw Exception(res.data['message'] ?? "Failed to get video info");
      }

      // 3. اختيار أفضل رابط للتحميل
      // نحاول البحث عن جودة متوسطة (720p) للحفاظ على المساحة، أو نأخذ الرابط المباشر
      String? downloadUrl;
      final data = res.data;
      
      if (data['availableQualities'] != null) {
        List qualities = data['availableQualities'];
        // محاولة إيجاد 720p
        var q720 = qualities.firstWhere(
          (q) => q['quality'] == 720, 
          orElse: () => null
        );
        
        if (q720 != null) {
          downloadUrl = q720['url'];
        } else if (qualities.isNotEmpty) {
          // إذا لم يوجد 720، نأخذ أول جودة متاحة
          downloadUrl = qualities.first['url'];
        }
      }
      
      // Fallback
      if (downloadUrl == null && data['url'] != null) {
        downloadUrl = data['url'];
      }

      if (downloadUrl == null) {
        throw Exception("No valid download link found");
      }

      // 4. تجهيز مسار الحفظ (Cleaning Names for Paths)
      final appDir = await getApplicationDocumentsDirectory();
      
      // إزالة الرموز الخاصة من الأسماء لتجنب أخطاء نظام الملفات
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // اسم الملف المؤقت والنهائي (المشفر)
      final tempPath = '${dir.path}/$lessonId.temp';
      final savePath = '${dir.path}/$lessonId.enc';

      // 5. بدء التحميل
      await _dio.download(
        downloadUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      // 6. تشفير الملف (Encrypt)
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        final bytes = await tempFile.readAsBytes();
        
        // استخدام EncryptionHelper لتشفير البيانات
        final encrypted = EncryptionHelper.encrypter.encryptBytes(
          bytes, 
          iv: EncryptionHelper.iv
        );
        
        // حفظ البيانات المشفرة
        final finalFile = File(savePath);
        await finalFile.writeAsBytes(encrypted.bytes);
        
        // حذف الملف المؤقت المكشوف
        await tempFile.delete();
      } else {
        throw Exception("Download failed: Temp file not created");
      }

      // 7. حفظ البيانات في قاعدة البيانات المحلية (Hive) للوصول إليها لاحقاً
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

      // إعلام النجاح
      onComplete();

    } catch (e, stack) {
      // تسجيل الخطأ
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed: $lessonId');
      onError(e.toString());
    }
  }
}
