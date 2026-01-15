import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter/foundation.dart'; // اختياري لطباعة DebugPrint أثناء التطوير

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// تقوم هذه الدالة بجلب الروابط وترتيبها
  /// تعيد Map المفتاح فيها هو اسم الجودة، والقيمة هي الرابط
  Future<Map<String, String>> getVideoQualities(String videoId) async {
    // 1. تسجيل بدء العملية مع المعرف
    FirebaseCrashlytics.instance.log("🚀 YT_Service: Start fetching for ID: $videoId");

    try {
      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      
      // تسجيل معلومات المانيفست (عدد المسارات المتاحة)
      FirebaseCrashlytics.instance.log(
        "📦 YT_Service: Manifest Fetched. "
        "Muxed: ${manifest.muxed.length}, "
        "VideoOnly: ${manifest.video.length}, "
        "Audio: ${manifest.audio.length}"
      );

      Map<String, String> qualities = {};

      // 1. إضافة الروابط المدمجة (Muxed)
      for (var stream in manifest.muxed) {
        String quality = stream.videoQualityLabel;
        if (stream.container.name == 'mp4' || !qualities.containsKey(quality)) {
          qualities[quality] = stream.url.toString();
        }
      }

      // 2. إضافة الروابط المنفصلة (Video Only) ودمجها مع أفضل صوت
      var audioStream = manifest.audio.withHighestBitrate();
      String audioUrl = audioStream.url.toString();

      for (var stream in manifest.video) {
        // نتجاهل الجودات الموجودة مسبقاً إلا إذا كانت غير موجودة
        if (!qualities.containsKey(stream.videoQualityLabel)) {
           // دمج الفيديو مع الصوت بفاصل |
           qualities[stream.videoQualityLabel] = "${stream.url}|$audioUrl";
        }
      }

      // 3. ✅ (مهم) تسجيل الرد النهائي الذي سيرسل للمشغل في Firebase
      FirebaseCrashlytics.instance.log("✅ YT_Service: FINAL OUTPUT MAP -> $qualities");

      return qualities;

    } catch (e, stack) {
      // 4. تسجيل الخطأ بالتفصيل مع StackTrace
      FirebaseCrashlytics.instance.log("❌ YT_Service: Failed to fetch streams for $videoId");
      
      await FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'YoutubeExplode Fetch Error ($videoId)',
        fatal: false
      );
      
      throw Exception("Error fetching YouTube streams: $e");
    }
  }

  /// استخراج معرف الفيديو من الرابط أو النص
  String? extractVideoId(String text) {
    try {
      final id = VideoId(text).value;
      // تسجيل محاولة استخراج ناجحة
      FirebaseCrashlytics.instance.log("🔍 YT_Service: Extracted ID $id from input");
      return id;
    } catch (e) {
      FirebaseCrashlytics.instance.log("⚠️ YT_Service: Failed to extract ID from: $text");
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}
