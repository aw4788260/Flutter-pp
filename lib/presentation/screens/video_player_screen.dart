import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ✅ مكتبات MediaKit
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/encryption_helper.dart';
import '../../core/services/app_state.dart'; // ✅ تمت إضافة هذا الاستيراد للوصول لبيانات المستخدم
// ✅ استيراد خدمة البروكسي المحلي
import '../../core/services/local_proxy.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.streams,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  // ✅ تعريف خدمة البروكسي
  final LocalProxyService _proxyService = LocalProxyService();

  String _currentQuality = "";
  List<String> _sortedQualities = [];
  double _currentSpeed = 1.0;

  bool _isError = false;
  String _errorMessage = "";
  
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  Timer? _screenRecordingTimer;

  final Map<String, String> _nativeHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12) ExoPlayerLib/2.18.1',
  };

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("🎬 MediaKit Player: Init Started");

    // تفعيل ملء الشاشة فوراً
    _enterFullScreenMode();

    // ✅ بدء تشغيل البروكسي
    _startProxyServer();

    _player = Player();
    
    // ✅ إعداد الكونترولر
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _player.stream.error.listen((error) {
      FirebaseCrashlytics.instance.recordError(
        Exception(error), 
        StackTrace.current, 
        reason: "🚨 MediaKit Stream Error"
      );
      
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "Playback Error: $error";
        });
      }
    });

    _setupScreenProtection();
    _loadUserData();
    _startWatermarkAnimation();
    _parseQualities();
  }

  // ✅ دالة تشغيل البروكسي مع تسجيل الأخطاء
  Future<void> _startProxyServer() async {
    try {
      FirebaseCrashlytics.instance.log("🔌 Starting Local Proxy...");
      await _proxyService.start();
      FirebaseCrashlytics.instance.log("✅ Local Proxy Started on port ${_proxyService.port}");
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: "🔥 Proxy Start Failed");
    }
  }

  Future<void> _enterFullScreenMode() async {
    // ✅ استخدام immersiveSticky لإخفاء أشرطة النظام بالكامل
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFullScreenMode() async {
    // ✅ العودة للوضع اليدوي الطبيعي بدلاً من edgeToEdge لمنع تداخل الواجهة في الصفحات الأخرى
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _setupScreenProtection() async {
    try {
      await WakelockPlus.enable();
      await ScreenProtector.protectDataLeakageOn();
      await ScreenProtector.preventScreenshotOn();

      _screenRecordingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        final isRecording = await ScreenProtector.isRecording();
        if (isRecording) {
          FirebaseCrashlytics.instance.log("⚠️ Screen Recording Detected!");
          _handleScreenRecordingDetected();
        }
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: "Screen Protection Error");
    }
  }

  void _handleScreenRecordingDetected() {
    _player.pause();
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("⚠️ Security Alert", style: TextStyle(color: Colors.red)),
          content: const Text("Screen recording is not allowed."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("Exit"),
            )
          ],
        ),
      );
    }
  }

  // ✅ تعديل: جلب رقم الهاتف بشكل أولي من AppState ثم Hive
  void _loadUserData() {
    String displayText = '';
    
    // 1. المحاولة الأولى: من الذاكرة الحية (AppState)
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] ?? '';
    }

    // 2. المحاولة الثانية: من التخزين المحلي (Hive)
    if (displayText.isEmpty) {
      try {
        if (Hive.isBoxOpen('auth_box')) {
          var box = Hive.box('auth_box');
          // الأولوية لرقم الهاتف، ثم اسم المستخدم
          displayText = box.get('phone') ?? box.get('username') ?? '';
        }
      } catch (e) {
        FirebaseCrashlytics.instance.log("⚠️ Failed to load user data for watermark: $e");
      }
    }

    setState(() {
      _watermarkText = displayText.isNotEmpty ? displayText : 'User';
    });
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
      FirebaseCrashlytics.instance.log("❌ No streams provided to player");
      setState(() {
        _isError = true;
        _errorMessage = "No video sources available";
      });
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    _currentQuality = _sortedQualities.contains("480p") 
        ? "480p" 
        : (_sortedQualities.isNotEmpty ? _sortedQualities.first : "");

    if (_currentQuality.isNotEmpty) {
      FirebaseCrashlytics.instance.log("▶️ Initial Quality Selected: $_currentQuality");
      _playVideo(widget.streams[_currentQuality]!);
    }
  }

  Future<void> _playVideo(String url, {Duration? startAt}) async {
    try {
      String playUrl = url;
      FirebaseCrashlytics.instance.log("🔄 Preparing to play: $url");

      if (!url.startsWith('http')) {
        final file = File(url);
        if (!await file.exists()) {
           FirebaseCrashlytics.instance.recordError(
             Exception("Offline file missing"), 
             StackTrace.current, 
             reason: "File path: $url"
           );
           throw Exception("Offline file missing");
        }

        playUrl = 'http://127.0.0.1:${_proxyService.port}/video?path=${Uri.encodeComponent(file.path)}';
        FirebaseCrashlytics.instance.log("🔗 Proxy URL Generated: $playUrl");
      } 
      
      await _player.open(Media(playUrl, httpHeaders: _nativeHeaders), play: false);
      
      if (startAt != null) {
        await _player.seek(startAt);
      }

      if (_currentSpeed != 1.0) {
        await _player.setRate(_currentSpeed);
      }

      await _player.play();
      FirebaseCrashlytics.instance.log("✅ Playback started successfully");

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: '📽️ MediaKit Play Failed');
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "Failed to load video.";
        });
      }
    }
  }

  Future<void> _seekRelative(Duration amount) async {
    try {
      final currentPos = _player.state.position;
      final newPos = currentPos + amount;
      await _player.seek(newPos);
    } catch (e) {
      FirebaseCrashlytics.instance.log("⚠️ Seek Error: $e");
    }
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16), 
              child: Text("Settings", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
            ),
            const Divider(color: Colors.white24),
            
            ListTile(
              leading: const Icon(LucideIcons.monitor, color: Colors.white),
              title: Text("Quality: $_currentQuality", style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showQualitySelection();
              },
            ),

            ListTile(
              leading: const Icon(LucideIcons.gauge, color: Colors.white),
              title: Text("Speed: ${_currentSpeed}x", style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showSpeedSelection();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQualitySelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _sortedQualities.reversed.map((q) => ListTile(
            title: Text(q, style: TextStyle(color: q == _currentQuality ? AppColors.accentYellow : Colors.white)),
            trailing: q == _currentQuality ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
            onTap: () {
              Navigator.pop(ctx);
              if (q != _currentQuality) {
                FirebaseCrashlytics.instance.log("🔄 Switching Quality to: $q");
                final currentPos = _player.state.position;
                setState(() { _currentQuality = q; _isError = false; });
                _playVideo(widget.streams[q]!, startAt: currentPos);
              }
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showSpeedSelection() {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: speeds.map((s) => ListTile(
            title: Text("${s}x", style: TextStyle(color: s == _currentSpeed ? AppColors.accentYellow : Colors.white)),
            trailing: s == _currentSpeed ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _currentSpeed = s);
              _player.setRate(s);
            },
          )).toList(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    FirebaseCrashlytics.instance.log("🛑 Disposing Player Screen");
    _watermarkTimer?.cancel();
    _screenRecordingTimer?.cancel();
    
    _proxyService.stop();
    _player.dispose();
    
    _exitFullScreenMode();
    ScreenProtector.protectDataLeakageOff();
    ScreenProtector.preventScreenshotOff();
    WakelockPlus.disable();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) _exitFullScreenMode();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // ✅ إضافة هذا السطر لمنع تغير حجم الواجهة عند ظهور الكيبورد أو التداخلات
        resizeToAvoidBottomInset: false,
        // ✅ استخدام Stack مباشرة لملء الشاشة بالكامل
        body: Stack(
          children: [
            Positioned.fill(
              // ✅ 1. إزالة Center لضمان أن عناصر التحكم تملأ الشاشة كاملة ولا تتقيد بأبعاد الفيديو فقط
              child: _isError
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                          const SizedBox(height: 16),
                          Text(_errorMessage, style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                               FirebaseCrashlytics.instance.log("🔄 User Clicked Retry");
                               setState(() => _isError = false);
                               _playVideo(widget.streams[_currentQuality]!);
                            }, 
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentYellow),
                            child: const Text("Retry", style: TextStyle(color: Colors.black)),
                          )
                        ],
                      ),
                    )
                  : MaterialVideoControlsTheme(
                      // ✅ 2. ضبط الحشوة (Padding) إلى صفر في كلا الوضعين لمنع المكتبة من إضافة مساحة للنوتش المخفي
                      normal: MaterialVideoControlsThemeData(
                        padding: EdgeInsets.zero, 
                        topButtonBar: [
                          const SizedBox(width: 14),
                          MaterialCustomButton(
                            onPressed: () {
                              _exitFullScreenMode();
                              Navigator.pop(context);
                            },
                            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            widget.title,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                        primaryButtonBar: [
                          const Spacer(flex: 2),
                          MaterialCustomButton(
                            onPressed: () => _seekRelative(const Duration(seconds: -10)),
                            icon: const Icon(Icons.replay_10, size: 36, color: Colors.white),
                          ),
                          const SizedBox(width: 24),
                          const MaterialPlayOrPauseButton(iconSize: 56),
                          const SizedBox(width: 24),
                          MaterialCustomButton(
                            onPressed: () => _seekRelative(const Duration(seconds: 10)),
                            icon: const Icon(Icons.forward_10, size: 36, color: Colors.white),
                          ),
                          const Spacer(flex: 2),
                        ],
                        bottomButtonBar: [
                          const SizedBox(width: 24),
                          const MaterialPositionIndicator(),
                          const Spacer(),
                          const MaterialSeekBar(),
                          const Spacer(),
                          MaterialCustomButton(
                            onPressed: _showSettingsSheet,
                            icon: const Icon(LucideIcons.settings, color: Colors.white),
                          ),
                          const SizedBox(width: 24),
                        ],
                        automaticallyImplySkipNextButton: false,
                        automaticallyImplySkipPreviousButton: false,
                      ),
                      fullscreen: const MaterialVideoControlsThemeData(
                        padding: EdgeInsets.zero, // ✅ هام جداً لمنع الإزاحة
                        displaySeekBar: true,
                        automaticallyImplySkipNextButton: false,
                        automaticallyImplySkipPreviousButton: false,
                      ),
                      child: Video(
                        controller: _controller,
                        fit: BoxFit.contain,
                        // ✅ 3. إجبار الفيديو على أخذ أبعاد الشاشة بالكامل لضمان تموضع عناصر التحكم في الحواف
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                      ),
                    ),
            ),

            if (!_isError)
              AnimatedAlign(
                duration: const Duration(seconds: 2), 
                curve: Curves.easeInOut,
                alignment: _watermarkAlignment,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      // ✅ زيادة التباين (أغمق قليلاً)
                      color: Colors.black.withOpacity(0.6), 
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _watermarkText,
                      style: TextStyle(
                        // ✅ زيادة وضوح النص
                        color: Colors.white.withOpacity(0.9), 
                        fontWeight: FontWeight.bold,
                        fontSize: 12, // الحفاظ على الحجم
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
