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
import 'package:dio/dio.dart'; // ✅ ضروري لكود الطباعة
import '../../core/constants/app_colors.dart';
import '../../core/services/local_proxy.dart'; // ✅ لاستخدام البروكسي

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams;
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
  final LocalProxyService _proxy = LocalProxyService(); // ✅ البروكسي
  
  String _currentQuality = "";
  List<String> _sortedQualities = [];
  bool _isError = false;
  String _errorMessage = "";

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";
  Timer? _screenRecordingTimer;

  // الهيدر المستخدم في الأندرويد الأصلي
  final Map<String, String> _nativeHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12) ExoPlayerLib/2.18.1',
  };

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("🎬 VideoPlayerScreen: Init");
    WidgetsBinding.instance.addObserver(this);

    _startProxy(); // تشغيل البروكسي
    _setupScreenProtection();
    _loadUserData();
    _startWatermarkAnimation();
    _parseQualities();
  }

  Future<void> _startProxy() async {
    await _proxy.start();
  }

  Future<void> _setupScreenProtection() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
      ]);
      await WakelockPlus.enable();
      await ScreenProtector.protectDataLeakageOn(); 
      await ScreenProtector.preventScreenshotOn();

      _screenRecordingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (await ScreenProtector.isRecording()) _handleScreenRecordingDetected();
      });
    } catch (_) {}
  }

  void _handleScreenRecordingDetected() {
    _videoPlayerController.pause();
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("⚠️ Security Alert", style: TextStyle(color: Colors.red)),
          content: const Text("Screen recording detected."),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text("Exit"),
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
        setState(() => _watermarkText = box.get('phone') ?? box.get('username') ?? 'User');
      }
    } catch (_) {}
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          _watermarkAlignment = Alignment(
            (random.nextDouble() * 1.6) - 0.8,
            (random.nextDouble() * 1.6) - 0.8
          );
        });
      }
    });
  }

  void _parseQualities() {
    if (widget.streams.isEmpty) {
      setState(() { _isError = true; _errorMessage = "No sources"; });
      return;
    }
    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });
    _currentQuality = _sortedQualities.contains("480p") ? "480p" : _sortedQualities.first;
    if (_currentQuality.isNotEmpty) _initializePlayer(widget.streams[_currentQuality]!);
  }

  void _videoListener() {
    if (_videoPlayerController.value.hasError) {
      final error = _videoPlayerController.value.errorDescription ?? "Unknown";
      FirebaseCrashlytics.instance.log("🚨 PLAYER ERROR: $error");
      if (!_isError && mounted) {
        setState(() { _isError = true; _errorMessage = "Playback Error"; });
      }
    }
  }

  Future<void> _initializePlayer(String url) async {
    FirebaseCrashlytics.instance.log("🎬 Init: $url");

    // تنظيف القديم
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
      // 🕵️‍♂️ كود الجاسوس (Probe) لطباعة رد جوجل
      if (url.startsWith('http')) {
        try {
          FirebaseCrashlytics.instance.log("🕵️ PROBE: Sending test request...");
          final dio = Dio();
          final response = await dio.get(
            url,
            options: Options(
              headers: _nativeHeaders, // نفس الهيدر
              validateStatus: (status) => true, // قبول أي حالة
              responseType: ResponseType.plain, // قراءة النص
            ),
          );
          
          FirebaseCrashlytics.instance.log("🕵️ PROBE Status: ${response.statusCode}");
          if (response.statusCode != 200) {
            String body = response.data.toString();
            if (body.length > 1000) body = body.substring(0, 1000); // أول 1000 حرف
            FirebaseCrashlytics.instance.log("🚨 PROBE RESPONSE BODY: $body");
          } else {
            FirebaseCrashlytics.instance.log("✅ PROBE Success (200 OK).");
          }
        } catch (e) {
          FirebaseCrashlytics.instance.log("⚠️ PROBE Failed: $e");
        }
      }
      // 🕵️‍♂️ انتهى الجاسوس

      // ✅ التجهيز للمشغل
      if (!url.startsWith('http')) {
        // سيناريو الأوفلاين (استخدام البروكسي المحلي مع البث)
        final proxyUrl = 'http://127.0.0.1:8080/video?path=${Uri.encodeComponent(url)}';
        FirebaseCrashlytics.instance.log("🔗 Playing via Proxy: $proxyUrl");
        
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(proxyUrl),
          // لا هيدرز للبروكسي المحلي
        );
      } else {
        // سيناريو الأونلاين (يوتيوب)
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: _nativeHeaders, // استخدام الهيدر الأصلي
          formatHint: VideoFormat.hls,
        );
      }

      _videoPlayerController.addListener(_videoListener);
      await _videoPlayerController.initialize();
      
      if (currentPos > Duration.zero) await _videoPlayerController.seekTo(currentPos);

      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoPlayerController,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          allowedScreenSleep: false,
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accentYellow,
            handleColor: AppColors.accentYellow,
            backgroundColor: Colors.grey.withOpacity(0.5),
            bufferedColor: Colors.white24,
          ),
          playbackSpeeds: [0.5, 1.0, 1.25, 1.5, 2.0],
          additionalOptions: (context) => [
            OptionItem(
              onTap: (ctx) { Navigator.pop(ctx); _showQualitySheet(); },
              iconData: LucideIcons.settings,
              title: 'Quality: $_currentQuality',
            )
          ],
          errorBuilder: (ctx, msg) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.accentOrange, size: 40),
                const SizedBox(height: 10),
                Text("Error: $msg", style: const TextStyle(color: Colors.white)),
                ElevatedButton(
                  onPressed: () { setState(() => _isError = false); _initializePlayer(url); },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentYellow),
                  child: const Text("Retry", style: TextStyle(color: Colors.black)),
                )
              ],
            ),
          ),
        );
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Init Failed: $url');
      if (mounted) setState(() { _isError = true; _errorMessage = "Load Failed"; });
    }
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text("Select Quality", style: TextStyle(color: Colors.white, fontSize: 18))),
            ..._sortedQualities.reversed.map((q) => ListTile(
              title: Text(q, style: TextStyle(color: q == _currentQuality ? AppColors.accentYellow : Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                if (q != _currentQuality) {
                  setState(() { _currentQuality = q; _chewieController = null; _isError = false; });
                  _initializePlayer(widget.streams[q]!);
                }
              },
            )),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watermarkTimer?.cancel();
    _screenRecordingTimer?.cancel();
    _proxy.stop(); // ✅ إيقاف البروكسي
    
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
          if (!_isError)
            AnimatedAlign(
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOut,
              alignment: _watermarkAlignment,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                  child: Text(_watermarkText, style: TextStyle(color: Colors.white.withOpacity(0.3), fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.none)),
                ),
              ),
            ),
          Positioned(
            top: 20, left: 20,
            child: SafeArea(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.none)),
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
