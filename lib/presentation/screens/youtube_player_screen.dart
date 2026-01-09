import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';

class YoutubePlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;

  const YoutubePlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
  });

  @override
  State<YoutubePlayerScreen> createState() => _YoutubePlayerScreenState();
}

class _YoutubePlayerScreenState extends State<YoutubePlayerScreen> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    // 1. إعداد المشغل
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        hideControls: false, // إظهار أزرار التحكم الافتراضية لليوتيوب
        forceHD: false,      // نجعله false لتوفير البيانات
        isLive: false,
        loop: false,
      ),
    );
  }

  @override
  void deactivate() {
    // إيقاف الفيديو عند الخروج مؤقتاً
    _controller.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.dispose();
    // إعادة توجيه الشاشة للوضع الرأسي عند الخروج
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: AppColors.accentYellow,
        progressColors: const ProgressBarColors(
          playedColor: AppColors.accentYellow,
          handleColor: AppColors.accentYellow,
        ),
        onReady: () {
          // الكود هنا يعمل عندما يكون المشغل جاهزاً
        },
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: player,
          ),
        );
      },
    );
  }
}
