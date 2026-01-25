import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';

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
   
  // متغيرات العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _userIdText = ""; 

  @override
  void initState() {
    super.initState();
    
    // ✅ 1. تفعيل وضع ملء الشاشة الأفقي
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 2. جلب رقم الهاتف وبدء التحريك
    _getUserId();
    _startWatermarkAnimation();

    // ✅ 3. إعداد المشغل
    try {
      _controller = YoutubePlayerController(
        initialVideoId: widget.videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          hideControls: false,
          forceHD: false,
          isLive: false,
          loop: false,
          enableCaption: false, 
          disableDragSeek: false, 
        ),
      )..addListener(_playerListener);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Youtube Player Init Error');
    }
  }

  void _playerListener() {
    if (_controller.value.hasError) {
      FirebaseCrashlytics.instance.log("Youtube Player Error: ${_controller.value.errorCode}");
    }
  }

  void _getUserId() {
    String displayText = '';
     
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] ?? '';
    }

    if (displayText.isEmpty) {
      try {
        if (Hive.isBoxOpen('auth_box')) {
          var box = Hive.box('auth_box');
          displayText = box.get('phone') ?? box.get('username') ?? '';
        }
      } catch (e) {
        // ignore
      }
    }

    setState(() {
      _userIdText = displayText.isNotEmpty ? displayText : 'User';
    });
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          double x = (random.nextDouble() * 1.8) - 0.9;
          double y = (random.nextDouble() * 1.6) - 0.8;
          _watermarkAlignment = Alignment(x, y);
        });
      }
    });
  }

  @override
  void deactivate() {
    _controller.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    _watermarkTimer?.cancel();
    _controller.removeListener(_playerListener);
    _controller.dispose();
     
    // ✅ استعادة وضع النظام الطبيعي (إظهار الأشرطة العلوية والسفلية)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
     
    // ✅ استعادة توجيه الشاشة للوضع الطبيعي (السماح بالتدوير أو العودة للعمودي)
    // يمكنك استخدام DeviceOrientation.portraitUp إذا كنت تريد إجبار الوضع العمودي فقط
    SystemChrome.setPreferredOrientations(DeviceOrientation.values); 
     
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. مشغل الفيديو
          Center(
            child: YoutubePlayer(
              controller: _controller,
              showVideoProgressIndicator: true,
              // 🔥 تم حذف const هنا
              progressIndicatorColor: AppColors.accentYellow,
              progressColors: ProgressBarColors(
                // 🔥 تم حذف const هنا
                playedColor: AppColors.accentYellow,
                // 🔥 تم حذف const هنا
                handleColor: AppColors.accentYellow,
              ),
              bottomActions: [
                const CurrentPosition(),
                const SizedBox(width: 10),
                const ProgressBar(isExpanded: true),
                const SizedBox(width: 10),
                const RemainingDuration(),
                const PlaybackSpeedButton(),
              ],
            ),
          ),

          // 2. العلامة المائية المتحركة
          AnimatedAlign(
            duration: const Duration(seconds: 2),
            curve: Curves.easeInOut,
            alignment: _watermarkAlignment,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6), 
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _userIdText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9), 
                    fontWeight: FontWeight.bold,
                    fontSize: 11, 
                  ),
                ),
              ),
            ),
          ),

          // 3. زر الرجوع والعنوان
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
