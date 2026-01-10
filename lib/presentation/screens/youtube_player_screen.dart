import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ استيراد Crashlytics
import 'package:hive_flutter/hive_flutter.dart'; // ✅ استيراد Hive لجلب بيانات المستخدم
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
  String _userIdText = "User ID"; 

  @override
  void initState() {
    super.initState();
    
    // ✅ 1. إجبار الشاشة على الوضع الأفقي (ملء الشاشة) عند الفتح
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 2. جلب معرف المستخدم وبدء التحريك
    _getUserId();
    _startWatermarkAnimation();

    // ✅ 3. إعداد المشغل مع تسجيل الأخطاء
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
        ),
      )..addListener(_playerListener); // الاستماع للأخطاء
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Youtube Player Init Error');
    }
  }

  // مستمع لاكتشاف أخطاء التشغيل
  void _playerListener() {
    if (_controller.value.hasError) {
      FirebaseCrashlytics.instance.log("Youtube Player Error: ${_controller.value.errorCode}");
    }
  }

  // دالة جلب معرف المستخدم من Hive
  void _getUserId() {
    try {
      if (Hive.isBoxOpen('auth_box')) {
        var box = Hive.box('auth_box');
        // نستخدم الاسم أو رقم الهاتف أو المعرف
        setState(() {
          _userIdText = box.get('username') ?? box.get('phone') ?? box.get('user_id') ?? 'Student';
        });
      }
    } catch (e) {
      // تجاهل الخطأ في حالة عدم فتح الصندوق
    }
  }

  // ✅ 4. منطق تحريك العلامة المائية (تتحرك وتثبت قليلاً)
  void _startWatermarkAnimation() {
    // كل 4 ثواني نغير المكان
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          // توليد محاذاة عشوائية بين -0.8 و 0.8 لتجنب الحواف القصوى
          final random = Random();
          double x = (random.nextDouble() * 1.6) - 0.8;
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
    _watermarkTimer?.cancel(); // إيقاف التايمر
    _controller.removeListener(_playerListener);
    _controller.dispose();
    
    // ✅ إعادة الشاشة للوضع الرأسي عند الخروج
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
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          // نستخدم Stack لوضع العلامة المائية فوق الفيديو
          body: Stack(
            children: [
              // 1. الفيديو في المنتصف
              Center(child: player),

              // 2. العلامة المائية المتحركة
              AnimatedAlign(
                duration: const Duration(seconds: 2), // مدة الحركة (تتحرك ببطء)
                curve: Curves.easeInOut,
                alignment: _watermarkAlignment,
                child: IgnorePointer( // لكي لا تمنع اللمس على الفيديو
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3), // خلفية نصف شفافة
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _userIdText,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5), // نص نصف شفاف
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),

              // 3. زر الرجوع والعنوان (مخصص ليظهر فوق الفيديو في وضع ملء الشاشة)
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
                          child: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      },
    );
  }
}
