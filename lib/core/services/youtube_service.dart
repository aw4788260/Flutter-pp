import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// تقوم هذه الدالة بجلب الروابط وترتيبها
  Future<Map<String, String>> getVideoQualities(String videoId) async {
    FirebaseCrashlytics.instance.log("🚀 YT_Service: Start fetching for ID: $videoId");

    try {
      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      Map<String, String> qualities = {};

      // 1. معالجة الروابط المدمجة (Muxed) - تعمل مباشرة (عادة 360p, 720p)
      for (var stream in manifest.muxed) {
        String quality = stream.videoQualityLabel;
        // نفضل mp4 دائماً للتوافق
        if (stream.container.name == 'mp4') {
          qualities[quality] = stream.url.toString();
        }
      }

      // 2. معالجة الروابط المنفصلة (Adaptive) - للجودات العالية (1080p, 2K, 4K)
      // يوتيوب يفصل الفيديو عن الصوت هنا، لذا يجب دمجهم يدوياً
      
      // أ) الحصول على أفضل ملف صوتي
      var audioStream = manifest.audio.withHighestBitrate();
      String audioUrl = audioStream.url.toString();

      // ب) دمج ملف الفيديو مع ملف الصوت
      for (var stream in manifest.video) {
        // نتأكد أنها MP4 ونتجاهل الجودات التي حصلنا عليها بالفعل من Muxed (لتجنب التكرار)
        if (stream.container.name == 'mp4' && !qualities.containsKey(stream.videoQualityLabel)) {
           // نقوم بدمج رابط الفيديو مع رابط الصوت بفاصل "|"
           // المشغل سيقوم بفك هذا الفاصل لاحقاً
           qualities[stream.videoQualityLabel] = "${stream.url}|$audioUrl";
        }
      }

      FirebaseCrashlytics.instance.log("✅ YT_Service: Extracted ${qualities.length} qualities");
      return qualities;

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'YoutubeExplode Fetch Error');
      throw Exception("Error fetching YouTube streams: $e");
    }
  }

  /// استخراج معرف الفيديو من الرابط أو النص
  String? extractVideoId(String text) {
    try {
      return VideoId(text).value;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}
