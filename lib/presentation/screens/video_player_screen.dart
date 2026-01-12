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
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; 
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

  final LocalProxyService _proxyService = LocalProxyService();

  String _currentQuality = "";
  List<String> _sortedQualities = [];
  double _currentSpeed = 1.0;

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitialized = false; // ✅ متغير لانتظار التهيئة
  
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
    // ✅ نقلنا كل عمليات البدء إلى دالة غير متزامنة لضمان الترتيب
    _initializePlayerScreen();
  }

  Future<void> _initializePlayerScreen() async {
    FirebaseCrashlytics.instance.log("🎬 MediaKit Player: Init Sequence Started");

    try {
      // 1. ✅ تفعيل وضع الغامرة (إخفاء الأزرار وشريط الحالة) لتجربة مشاهدة أفضل
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // 2. ✅ السماح بالتدوير التلقائي (عدم إجبار وضع معين)
      // هذا يسمح للمستخدم بقلب الهاتف لتدوير الفيديو، أو بقائه رأسياً إذا كان يحمل الهاتف رأسياً
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // 3. ✅ تشغيل البروكسي والانتظار
      await _startProxyServer();

      // 4. ✅ إنشاء المشغل بعد استقرار الشاشة
      _player = Player();
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: true,
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

      // 5. ✅ تحديد الجودة والتشغيل
      if (mounted) {
        setState(() {
          _isInitialized = true; // السماح بعرض الواجهة الآن
        });
        _parseQualities();
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: "Initialization Failed");
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "Init Failed: $e";
        });
      }
    }
  }

  Future<void> _startProxyServer() async {
    try {
      await _proxyService.start();
    } catch (e) {
      debugPrint("Proxy Error: $e");
    }
  }

  Future<void> _restoreSystemUI() async {
    // ✅ عند الخروج: إيقاف الفيديو، إعادة أشرطة النظام، وإعادة الوضع الرأسي (الافتراضي للتطبيقات)
    await _player.stop();
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
          _handleScreenRecordingDetected();
        }
      });
    } catch (e) {
      debugPrint("Screen protection error: $e");
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

  void _loadUserData() {
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
        debugPrint("Hive Error: $e");
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
      _playVideo(widget.streams[_currentQuality]!);
    }
  }

  Future<void> _playVideo(String url, {Duration? startAt}) async {
    try {
      String playUrl = url;

      if (!url.startsWith('http')) {
        final file = File(url);
        if (!await file.exists()) throw Exception("Offline file missing");
        playUrl = 'http://127.0.0.1:${_proxyService.port}/video?path=${Uri.encodeComponent(file.path)}';
      } 
      
      await _player.open(Media(playUrl, httpHeaders: _nativeHeaders), play: false);
      
      if (startAt != null) {
        await _player.seek(startAt);
      }

      if (_currentSpeed != 1.0) {
        await _player.setRate(_currentSpeed);
      }

      await _player.play();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Play Failed');
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
      await _player.seek(currentPos + amount);
    } catch (e) {/*ignore*/}
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
    _watermarkTimer?.cancel();
    _screenRecordingTimer?.cancel();
    _proxyService.stop();
    _player.dispose();
    _restoreSystemUI(); // ✅ استعادة الوضع الطبيعي عند الخروج
    ScreenProtector.protectDataLeakageOff();
    ScreenProtector.preventScreenshotOff();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ حساب المنطقة الآمنة السفلية لرفع عناصر التحكم عنها
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) _restoreSystemUI();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        // ✅ 1. هام: منع Scaffold من التعامل مع المناطق الآمنة لتجنب الإزاحة
        primary: false, 
        extendBody: true,
        
        // ✅ 2. استخدام StackFit.expand لملء الشاشة بالكامل
        body: Stack(
          fit: StackFit.expand,
          children: [
            // في حالة عدم الجاهزية، نعرض مؤشر تحميل أسود
            if (!_isInitialized)
              const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
            else if (_isError)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                    const SizedBox(height: 16),
                    Text(_errorMessage, style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                         setState(() => _isError = false);
                         _playVideo(widget.streams[_currentQuality]!);
                      }, 
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentYellow),
                      child: const Text("Retry", style: TextStyle(color: Colors.black)),
                    )
                  ],
                ),
              )
            else
              // ✅ 3. توسيط الفيديو لضمان عدم الإزاحة
              Center(
                child: MaterialVideoControlsTheme(
                  normal: MaterialVideoControlsThemeData(
                    // ✅ (هام جداً) هذا السطر يرفع عناصر التحكم عن الحافة السفلية بمقدار المنطقة الآمنة + 20 بكسل إضافية
                    padding: EdgeInsets.only(bottom: bottomPadding > 0 ? bottomPadding : 20, top: 20, left: 20, right: 20),
                    
                    bottomButtonBar: [
                      const MaterialPositionIndicator(),
                      const Spacer(),
                      const MaterialSeekBar(), // الآن سيظهر بشكل سليم لأنه محمي بالـ padding الخارجي
                      const Spacer(),
                      MaterialCustomButton(
                        onPressed: _showSettingsSheet,
                        icon: const Icon(LucideIcons.settings, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      // ✅ زر الخروج من الفيديو
                      MaterialCustomButton(
                        onPressed: () {
                          _restoreSystemUI();
                          Navigator.pop(context);
                        },
                        icon: const Icon(LucideIcons.minimize, color: Colors.white),
                      ),
                    ],
                    topButtonBar: [
                      MaterialCustomButton(
                        onPressed: () {
                          _restoreSystemUI();
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
                    automaticallyImplySkipNextButton: false,
                    automaticallyImplySkipPreviousButton: false,
                  ),
                  fullscreen: const MaterialVideoControlsThemeData(
                    // ✅ تطبيق نفس الـ Padding في وضع الـ fullscreen لضمان التناسق
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    displaySeekBar: true,
                    automaticallyImplySkipNextButton: false,
                    automaticallyImplySkipPreviousButton: false,
                  ),
                  child: Video(
                    controller: _controller,
                    // ✅ 5. إزالة القيود اليدوية والسماح له بأخذ حجم الـ Center
                    fit: BoxFit.contain, 
                  ),
                ),
              ),

            // العلامة المائية
            if (!_isError && _isInitialized)
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
                        color: Colors.white.withOpacity(0.4), 
                        fontWeight: FontWeight.bold,
                        fontSize: 12, 
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
