import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  
  // متغيرات العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _userIdText = ""; // سنضع فيه رقم الهاتف

  @override
  void initState() {
    super.initState();
    
    // ✅ 1. إجبار الشاشة على الوضع الأفقي (ملء الشاشة) عند الفتح
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
          // ✅ تم التعديل: إيقاف الترجمة التلقائية
          enableCaption: false, 
          // تعطيل زر ملء الشاشة لمنع التعارض مع العلامة المائية
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

  // ✅ تعديل: جلب رقم الهاتف فقط
  void _getUserId() {
    try {
      if (Hive.isBoxOpen('auth_box')) {
        var box = Hive.box('auth_box');
        setState(() {
          // الأولوية لرقم الهاتف، ثم الاسم، ثم المعرف
          _userIdText = box.get('phone') ?? box.get('username') ?? box.get('user_id') ?? 'Student';
        });
      }
    } catch (e) {
      // تجاهل الخطأ
    }
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          // توليد موقع عشوائي (تم توسيع النطاق قليلاً لتغطية الشاشة بشكل أفضل)
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
    
    // ✅ إعادة الشاشة للوضع الرأسي عند الخروج
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ تم إزالة YoutubePlayerBuilder واستخدام Scaffold مباشرة
    // لأننا أجبرنا الشاشة على الوضع الأفقي، فالصفحة كلها تعتبر "ملء شاشة"
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. مشغل الفيديو
          Center(
            child: YoutubePlayer(
              controller: _controller,
              showVideoProgressIndicator: true,
              progressIndicatorColor: AppColors.accentYellow,
              progressColors: const ProgressBarColors(
                playedColor: AppColors.accentYellow,
                handleColor: AppColors.accentYellow,
              ),
              // ✅ تخصيص أزرار التحكم لإزالة زر "ملء الشاشة" القياسي
              bottomActions: [
                const CurrentPosition(),
                const SizedBox(width: 10),
                const ProgressBar(isExpanded: true),
                const SizedBox(width: 10),
                const RemainingDuration(),
                const PlaybackSpeedButton(),
                // تم إزالة FullScreenButton() لضمان بقاء الواجهة كما هي
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
                // ✅ الحفاظ على نفس الحجم (Padding صغير)
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  // ✅ تم التعديل: زيادة التباين للخلفية لتصبح أوضح (كانت 0.3)
                  color: Colors.black.withOpacity(0.6), 
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _userIdText,
                  style: TextStyle(
                    // ✅ تم التعديل: جعل النص أبيض شبه ناصع (كان 0.4)
                    color: Colors.white.withOpacity(0.9), 
                    fontWeight: FontWeight.bold,
                    // ✅ الحفاظ على نفس حجم الخط
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
