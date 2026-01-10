import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ استيراد Crashlytics
import 'package:hive_flutter/hive_flutter.dart'; // ✅ استيراد Hive لجلب بيانات المستخدم
import '../../core/constants/app_colors.dart';

class VideoPlayerScreen extends StatefulWidget {
  // نستقبل قائمة الجودات { "1080p": "url", "720p": "url" }
  final Map<String, String> streams; 
  final String title;

  const VideoPlayerScreen({super.key, required this.streams, required this.title});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  
  String _currentQuality = "";
  List<String> _sortedQualities = [];

  // متغيرات العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _userIdText = "User ID"; 

  @override
  void initState() {
    super.initState();
    
    // ✅ 1. إجبار الشاشة على الوضع الأفقي (ملء الشاشة)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 2. جلب بيانات المستخدم وتشغيل العلامة المائية
    _getUserId();
    _startWatermarkAnimation();

    // بدء تهيئة الفيديو
    _parseQualities();
  }

  // دالة جلب معرف المستخدم
  void _getUserId() {
    try {
      if (Hive.isBoxOpen('auth_box')) {
        var box = Hive.box('auth_box');
        setState(() {
          _userIdText = box.get('username') ?? box.get('phone') ?? box.get('user_id') ?? 'Student';
        });
      }
    } catch (e) {
      // تجاهل الخطأ البسيط
    }
  }

  // منطق تحريك العلامة المائية
  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          // توليد موقع عشوائي داخل الشاشة
          double x = (random.nextDouble() * 1.6) - 0.8;
          double y = (random.nextDouble() * 1.6) - 0.8;
          _watermarkAlignment = Alignment(x, y);
        });
      }
    });
  }

  void _parseQualities() {
    if (widget.streams.isEmpty) {
      setState(() => _isError = true);
      FirebaseCrashlytics.instance.log("Video Error: No streams provided");
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    _currentQuality = _sortedQualities.contains("720p") ? "720p" : _sortedQualities.last;
    
    _initializePlayer(widget.streams[_currentQuality]!);
  }

  Future<void> _initializePlayer(String url) async {
    Duration currentPos = Duration.zero;
    if (_chewieController != null && _videoPlayerController.value.isInitialized) {
      currentPos = _videoPlayerController.value.position;
      _chewieController!.dispose();
      await _videoPlayerController.dispose();
    }

    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoPlayerController.initialize();
      
      if (currentPos > Duration.zero) {
        await _videoPlayerController.seekTo(currentPos);
      }

      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoPlayerController,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          showControls: true,
          
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accentYellow,
            handleColor: AppColors.accentYellow,
            backgroundColor: Colors.grey,
            bufferedColor: Colors.white24,
          ),
          
          playbackSpeeds: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
          
          additionalOptions: (context) {
            return <OptionItem>[
              OptionItem(
                onTap: (context) {
                  Navigator.pop(context); 
                  _showQualitySheet();   
                },
                iconData: LucideIcons.settings,
                title: 'Quality: $_currentQuality',
              ),
            ];
          },
          
          errorBuilder: (context, errorMessage) {
            // ✅ تسجيل أخطاء التشغيل الداخلية
            FirebaseCrashlytics.instance.log("Chewie Player Error: $errorMessage");
            return Center(child: Text(errorMessage, style: const TextStyle(color: Colors.white)));
          },
        );
      });
    } catch (e, stack) {
      // ✅ تسجيل فشل التهيئة
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Video Player Init Error: $url');
      setState(() => _isError = true);
    }
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Quality", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ..._sortedQualities.reversed.map((q) => ListTile(
                title: Text(q, style: TextStyle(color: q == _currentQuality ? AppColors.accentYellow : Colors.white)),
                trailing: q == _currentQuality ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (q != _currentQuality) {
                    setState(() {
                      _currentQuality = q;
                      _chewieController = null; 
                    });
                    _initializePlayer(widget.streams[q]!);
                  }
                },
              )),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _watermarkTimer?.cancel(); // إيقاف العلامة المائية
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    // ✅ إعادة الشاشة للوضع الرأسي
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // نستخدم Stack لدمج الفيديو والعلامة المائية
      body: Stack(
        children: [
          // 1. مشغل الفيديو
          Center(
            child: _isError
                ? const Text("Error loading video", style: TextStyle(color: AppColors.error))
                : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                    ? Chewie(controller: _chewieController!)
                    : const CircularProgressIndicator(color: AppColors.accentYellow),
          ),

          // 2. العلامة المائية المتحركة
          if (!_isError)
            AnimatedAlign(
              duration: const Duration(seconds: 2), // حركة ناعمة
              curve: Curves.easeInOut,
              alignment: _watermarkAlignment,
              child: IgnorePointer( // لكي لا تمنع اللمس
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _userIdText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),

          // 3. زر الرجوع (لأننا أخفينا الـ AppBar التقليدي لتوفير المساحة)
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                ),
              ),
            ),
          ),
          
          // 4. عنوان الفيديو بجانب زر الرجوع
          Positioned(
            top: 28, // محاذاة تقريبية مع الزر
            left: 70,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
