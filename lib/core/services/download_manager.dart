import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

      if (userId == null || deviceId == null) {
        throw Exception("User authentication missing");
      }

      // ✅ تصحيح: استخدام قيمة افتراضية للـ Secret لضمان العمل
      const String appSecret = String.fromEnvironment(
        'APP_SECRET', 
        defaultValue: 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only' 
      );

      String? finalUrl = downloadUrl;

      if (finalUrl == null) {
        final res = await _dio.get(
          '$_baseUrl/api/secure/get-video-id',
          queryParameters: {'lessonId': lessonId},
          options: Options(
            headers: {
              'x-user-id': userId,
              'x-device-id': deviceId,
              'x-app-secret': appSecret, // ✅ استخدام المتغير المصحح
            },
            validateStatus: (status) => status! < 500,
          ),
        );

        if (res.statusCode != 200) {
          throw Exception(res.data['message'] ?? "Failed to get video info (${res.statusCode})");
        }

        final data = res.data;
        
        // ✅ منع تحميل فيديوهات يوتيوب لأنها لا تعمل كملفات MP4
        if (data['youtube_video_id'] != null && (data['availableQualities'] == null || (data['availableQualities'] as List).isEmpty)) {
           throw Exception("YouTube videos cannot be downloaded offline.");
        }

        if (data['availableQualities'] != null) {
          List qualities = data['availableQualities'];
          var q720 = qualities.firstWhere((q) => q['quality'] == 720, orElse: () => null);
          
          if (q720 != null) {
            finalUrl = q720['url'];
          } else if (qualities.isNotEmpty) {
            finalUrl = qualities.first['url'];
          }
        }
        
        if (finalUrl == null && data['url'] != null) {
          finalUrl = data['url'];
        }
      }

      if (finalUrl == null) {
        throw Exception("No valid download link found");
      }

      final appDir = await getApplicationDocumentsDirectory();
      
      // تحسين دعم اللغة العربية في أسماء المجلدات
      final safeCourse = courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject = subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter = chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      
      final dir = Directory('${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final tempPath = '${dir.path}/$lessonId.temp';
      final savePath = '${dir.path}/$lessonId.enc';

      // ✅ تمرير الهيدرز عند التحميل أيضاً (في حال كان الرابط محمياً من السيرفر نفسه)
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
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        final fileSize = await tempFile.length();
        // التحقق من الملفات التالفة الصغيرة
        if (fileSize < 1024 * 10) { 
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
      _activeDownloads.remove(lessonId);
    }
  }
}
