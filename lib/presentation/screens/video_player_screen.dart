import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_protector/screen_protector.dart'; 
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ تأكد من وجود الاستيراد
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
  
  // إدارة الجودة
  String _currentQuality = "";
  List<String> _sortedQualities = [];
  bool _isError = false;

  // العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  // مراقبة تسجيل الشاشة
  Timer? _screenRecordingTimer;

  // ✅ هيدر المتصفح
  final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile; rv:100.0) Gecko/100.0 Firefox/100.0',
    'Accept': '*/*',
  };

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("🎬 VideoPlayerScreen: initState started"); // 📝 LOG
    WidgetsBinding.instance.addObserver(this);

    _setupScreenProtection();
    _loadUserData();
    _startWatermarkAnimation();
    _parseQualities();
  }

  /// 🛡️ إعداد الحماية
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
    FirebaseCrashlytics.instance.log("⚠️ Screen Recording Detected!");
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
    } catch (e) {
      FirebaseCrashlytics.instance.log("⚠️ Failed to load user data for watermark: $e");
    }
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
    FirebaseCrashlytics.instance.log("🎬 Parsing qualities: ${widget.streams.keys}"); // 📝 LOG
    
    if (widget.streams.isEmpty) {
      FirebaseCrashlytics.instance.recordError(Exception("No streams provided"), null, reason: 'Empty Streams Map');
      setState(() => _isError = true);
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    _currentQuality = _sortedQualities.contains("720p") 
        ? "720p" 
        : (_sortedQualities.isNotEmpty ? _sortedQualities.last : "");

    if (_currentQuality.isNotEmpty) {
      FirebaseCrashlytics.instance.log("🎬 Selected initial quality: $_currentQuality");
      _initializePlayer(widget.streams[_currentQuality]!);
    }
  }

  // ✅ دالة جديدة لمراقبة أخطاء الكنترولر الداخلية
  void _videoListener() {
    if (_videoPlayerController.value.hasError) {
      final error = _videoPlayerController.value.errorDescription;
      FirebaseCrashlytics.instance.log("🚨 INTERNAL PLAYER ERROR: $error");
      FirebaseCrashlytics.instance.recordError(Exception(error), null, reason: 'VideoController Error Listener');
      
      // يمكنك هنا إظهار رسالة خطأ للمستخدم إذا لزم الأمر
      if (!_isError && mounted) {
        setState(() => _isError = true);
      }
    }
  }

  Future<void> _initializePlayer(String url) async {
    FirebaseCrashlytics.instance.log("🎬 _initializePlayer started. URL: $url"); // 📝 LOG

    // حفظ الموقع الحالي
    Duration currentPos = Duration.zero;
    if (_chewieController != null) { // && _videoPlayerController.value.isInitialized (تم إزالته لتجنب أخطاء الفحص على كنترولر تالف)
      try {
        currentPos = _videoPlayerController.value.position;
        _videoPlayerController.removeListener(_videoListener); // إزالة المستمع القديم
        _chewieController!.dispose();
        await _videoPlayerController.dispose();
        FirebaseCrashlytics.instance.log("🎬 Old controller disposed.");
      } catch (e) {
        FirebaseCrashlytics.instance.log("⚠️ Error disposing old controller: $e");
      }
    }

    try {
      FirebaseCrashlytics.instance.log("🎬 Creating VideoPlayerController.networkUrl...");
      
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: _headers, 
      );

      // ✅ إضافة المستمع فوراً لالتقاط أخطاء التهيئة
      _videoPlayerController.addListener(_videoListener);

      FirebaseCrashlytics.instance.log("🎬 Calling initialize()...");
      await _videoPlayerController.initialize();
      FirebaseCrashlytics.instance.log("✅ Initialize successful.");
      
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
            FirebaseCrashlytics.instance.log("🚨 Chewie Error Builder: $errorMessage");
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 40),
                  const SizedBox(height: 10),
                  Text("Playback Error\n$errorMessage", 
                    textAlign: TextAlign.center, 
                    style: const TextStyle(color: Colors.white)
                  ),
                ],
              ),
            );
          },
        );
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Video Player Init Failed: $url');
      debugPrint("❌ Init Error: $e");
      if (mounted) setState(() => _isError = true);
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
                    FirebaseCrashlytics.instance.log("🎬 Switching quality to: $q");
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
    FirebaseCrashlytics.instance.log("🎬 VideoPlayerScreen: dispose");
    WidgetsBinding.instance.removeObserver(this);
    
    _watermarkTimer?.cancel();
    _screenRecordingTimer?.cancel();
    
    try {
      _videoPlayerController.removeListener(_videoListener);
      _videoPlayerController.dispose();
      _chewieController?.dispose();
    } catch (e) {
      FirebaseCrashlytics.instance.log("⚠️ Error disposing player controllers: $e");
    }
    
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
                ? const Text("Failed to load video. Check connection.", style: TextStyle(color: AppColors.error))
                : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized)
                    ? Chewie(controller: _chewieController!)
                    : const CircularProgressIndicator(color: AppColors.accentYellow),
          ),

          // 2. العلامة المائية المتحركة
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
