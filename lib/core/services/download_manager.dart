import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/encryption_helper.dart';

class DownloadManager {
  static final Dio _dio = Dio();
  // ✅ قائمة لتتبع التحميلات النشطة حالياً
  static final Set<String> _activeDownloads = {};

  final String _baseUrl = 'https://courses.aw478260.dpdns.org'; 

  // ✅ دالة التحقق مما إذا كان الملف قيد التحميل
  bool isFileDownloading(String id) {
    return _activeDownloads.contains(id);
  }

  // ✅ دالة التحقق مما إذا كان الملف محملاً بالفعل
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
    required Function(double) onProgress,
    required Function() onComplete,
    required Function(String) onError,
  }) async {
    // إضافة الملف لقائمة التحميلات النشطة
    _activeDownloads.add(lessonId);

    try {
      // 1. تجهيز بيانات المصادقة
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      if (userId == null || deviceId == null) {
        throw Exception("User authentication missing");
      }

      // 2. الاتصال بالـ API لجلب رابط الفيديو
      final res = await _dio.get(
        '$_baseUrl/api/secure/get-video-id',
        queryParameters: {'lessonId': lessonId},
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (res.statusCode != 200) {
        throw Exception(res.data['message'] ?? "Failed to get video info");
      }

      // 3. اختيار أفضل رابط للتحميل
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
          downloadUrl = qualities.first['url'];
        }
      }
      
      if (downloadUrl == null && data['url'] != null) {
        downloadUrl = data['url'];
      }

      if (downloadUrl == null) {
        throw Exception("No valid download link found");
      }

      // 4. تجهيز مسار الحفظ
      final appDir = await getApplicationDocumentsDirectory();
      
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

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

      // 6. تشفير الملف
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
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
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Download Failed: $lessonId');
      onError(e.toString());
    } finally {
      // إزالة الملف من قائمة التحميلات النشطة سواء نجح أو فشل
      _activeDownloads.remove(lessonId);
    }
  }
}
