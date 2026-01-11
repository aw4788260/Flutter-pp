import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_protector/screen_protector.dart'; 
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 
import '../../core/constants/app_colors.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams; // الجودات المتاحة
  final String title;

  const VideoPlayerScreen({
    super.key, 
    required this.streams, 
    required this.title
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with WidgetsBindingObserver {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  
  String _currentQuality = "";
  List<String> _sortedQualities = [];
  bool _isError = false;
  String _errorMessage = "";

  // العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  Timer? _screenRecordingTimer;

  // ❌❌❌ تم حذف الهيدرز المزيفة لأنها كانت تسبب المشكلة ❌❌❌
  // سيرفرات جوجل تفضل التعامل مع ExoPlayer مباشرة بدون User-Agent خاص بمتصفحات الويب

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("🎬 VideoPlayerScreen: initState started");
    WidgetsBinding.instance.addObserver(this);

    _setupScreenProtection();
    _loadUserData();
    _startWatermarkAnimation();
    _parseQualities();
  }

  Future<void> _setupScreenProtection() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await WakelockPlus.enable();
      await ScreenProtector.protectDataLeakageOn(); 
      await ScreenProtector.preventScreenshotOn();

      _screenRecordingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        final isRecording = await ScreenProtector.isRecording();
        if (isRecording) {
          _handleScreenRecordingDetected();
        }
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Screen Protection Init Failed');
    }
  }

  void _handleScreenRecordingDetected() {
    _videoPlayerController.pause();
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("⚠️ تنبيه أمني", style: TextStyle(color: Colors.red)),
          content: const Text("تم اكتشاف تسجيل للشاشة. يمنع تسجيل المحتوى."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("خروج"),
            )
          ],
        ),
      );
    }
  }

  void _loadUserData() {
    try {
      if (Hive.isBoxOpen('auth_box')) {
        var box = Hive.box('auth_box');
        setState(() {
          _watermarkText = box.get('phone') ?? box.get('username') ?? 'User';
        });
      }
    } catch (_) {}
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          double x = (random.nextDouble() * 1.6) - 0.8;
          double y = (random.nextDouble() * 1.6) - 0.8;
          _watermarkAlignment = Alignment(x, y);
        });
      }
    });
  }

  void _parseQualities() {
    if (widget.streams.isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = "No video sources available";
      });
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    // ترتيب الجودات
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    // اختيار جودة متوسطة افتراضياً
    _currentQuality = _sortedQualities.contains("480p") 
        ? "480p" 
        : (_sortedQualities.isNotEmpty ? _sortedQualities.first : "");

    if (_currentQuality.isNotEmpty) {
      _initializePlayer(widget.streams[_currentQuality]!);
    }
  }

  void _videoListener() {
    if (_videoPlayerController.value.hasError) {
      final error = _videoPlayerController.value.errorDescription ?? "Unknown error";
      FirebaseCrashlytics.instance.log("🚨 PLAYER ERROR: $error");
      
      if (!_isError && mounted) {
        setState(() {
          _isError = true;
          // رسالة خطأ واضحة
          _errorMessage = "Unable to play video. Link might be expired.";
        });
      }
    }
  }

  Future<void> _initializePlayer(String url) async {
    FirebaseCrashlytics.instance.log("🎬 Init Player: $url");

    // تنظيف المشغل القديم
    Duration currentPos = Duration.zero;
    if (_chewieController != null) {
      try {
        currentPos = _videoPlayerController.value.position;
        _videoPlayerController.removeListener(_videoListener);
        _chewieController!.dispose();
        await _videoPlayerController.dispose();
      } catch (_) {}
    }

    try {
      // ✅✅✅ التعديل هنا: إزالة httpHeaders تماماً ✅✅✅
      // هذا يجعل المشغل يستخدم الهوية الافتراضية للأندرويد (ExoPlayer)
      // وهي الهوية التي يقبلها يوتيوب بدون مشاكل.
      
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        // تم حذف httpHeaders: _headers
        
        // تلميح التنسيق يساعد المشغل على الفهم أسرع
        formatHint: VideoFormat.hls, 
      );

      _videoPlayerController.addListener(_videoListener);

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
          allowedScreenSleep: false,
          
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accentYellow,
            handleColor: AppColors.accentYellow,
            backgroundColor: Colors.grey.withOpacity(0.5),
            bufferedColor: Colors.white24,
          ),
          
          playbackSpeeds: [0.5, 1.0, 1.25, 1.5, 2.0],
          
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.accentOrange, size: 40),
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage.isNotEmpty ? _errorMessage : "Stream Error", 
                    textAlign: TextAlign.center, 
                    style: const TextStyle(color: Colors.white)
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                        setState(() => _isError = false);
                        _initializePlayer(url);
                    }, 
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentYellow),
                    child: const Text("Retry", style: TextStyle(color: Colors.black)),
                  )
                ],
              ),
            );
          },
        );
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Init Failed: $url');
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "Failed to load video.";
        });
      }
    }
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Select Quality", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(color: Colors.white24),
              ..._sortedQualities.reversed.map((q) => ListTile(
                title: Text(q, style: TextStyle(color: q == _currentQuality ? AppColors.accentYellow : Colors.white)),
                trailing: q == _currentQuality ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (q != _currentQuality) {
                    setState(() {
                      _currentQuality = q;
                      _chewieController = null;
                      _isError = false; 
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
    WidgetsBinding.instance.removeObserver(this);
    _watermarkTimer?.cancel();
    _screenRecordingTimer?.cancel();
    
    try {
      _videoPlayerController.removeListener(_videoListener);
      _videoPlayerController.dispose();
      _chewieController?.dispose();
    } catch (_) {}
    
    ScreenProtector.protectDataLeakageOff();
    ScreenProtector.preventScreenshotOff();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. المشغل
          Center(
            child: _isError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage, style: const TextStyle(color: Colors.white)),
                    ],
                  )
                : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized)
                    ? Chewie(controller: _chewieController!)
                    : const CircularProgressIndicator(color: AppColors.accentYellow),
          ),

          // 2. العلامة المائية
          if (!_isError)
            AnimatedAlign(
              duration: const Duration(seconds: 2), 
              curve: Curves.easeInOut,
              alignment: _watermarkAlignment,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3), 
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _watermarkText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3), 
                      fontWeight: FontWeight.bold,
                      fontSize: 12, 
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),

          // 3. زر الرجوع
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
                      style: const TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.none),
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
