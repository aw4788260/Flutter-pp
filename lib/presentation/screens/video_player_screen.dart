import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_protector/screen_protector.dart'; // ✅ المكتبة المطلوبة
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; 
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
  final _screenProtector = ScreenProtector(); // ✅ كائن الحماية

  String _currentQuality = "";
  List<String> _sortedQualities = [];
  double _currentSpeed = 1.0;

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitialized = false;
  bool _isSecurityViolation = false; // ✅ متغير لحالة المخالفة
  
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  Timer? _securityFallbackTimer; // مؤقت احتياطي

  final Map<String, String> _nativeHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12) ExoPlayerLib/2.18.1',
  };

  @override
  void initState() {
    super.initState();
    _initializePlayerScreen();
  }

  Future<void> _initializePlayerScreen() async {
    FirebaseCrashlytics.instance.log("🎬 MediaKit Player: Init");

    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      await _startProxyServer();

      _player = Player();
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );

      _player.stream.error.listen((error) {
        FirebaseCrashlytics.instance.recordError(Exception(error), StackTrace.current);
        if (mounted && !_isSecurityViolation) {
          setState(() {
            _isError = true;
            _errorMessage = "Playback Error: $error";
          });
        }
      });

      _setupRobustSecurity();
      
      _loadUserData();
      _startWatermarkAnimation();

      if (mounted) {
        setState(() => _isInitialized = true);
        _parseQualities();
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      if (mounted) setState(() { _isError = true; _errorMessage = "Init Failed: $e"; });
    }
  }

  Future<void> _startProxyServer() async {
    try { await _proxyService.start(); } catch (e) { debugPrint("Proxy Error: $e"); }
  }

  void _setupRobustSecurity() async {
    try {
      await WakelockPlus.enable();
      await _screenProtector.preventScreenshotOn();
      await _screenProtector.protectDataLeakageOn();

      _screenProtector.addListener(
        () {
          _triggerSecurityLock("تم اكتشاف محاولة تصوير للشاشة!");
        }, 
        (isRecording) {
          if (isRecording) {
            _triggerSecurityLock("تم اكتشاف تطبيق تسجيل فيديو يعمل في الخلفية!");
          }
        }
      );

      _securityFallbackTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (_isSecurityViolation) return; 
        
        bool isRecording = await _screenProtector.isRecording();
        if (isRecording) {
          _triggerSecurityLock("تم اكتشاف تسجيل للشاشة (فحص دوري)!");
        }
      });

    } catch (e) {
      debugPrint("Security Setup Error: $e");
    }
  }

  void _triggerSecurityLock(String reason) {
    if (_isSecurityViolation) return; 

    setState(() {
      _isSecurityViolation = true;
    });

    _player.pause(); 
    
    FirebaseCrashlytics.instance.log("🚨 Security Violation: $reason");

    if (mounted) {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "Security",
        barrierColor: Colors.black, 
        pageBuilder: (ctx, anim1, anim2) {
          return PopScope(
            canPop: false, 
            child: Scaffold(
              backgroundColor: const Color(0xFF1a0000), 
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.shieldAlert, size: 80, color: Colors.red),
                      const SizedBox(height: 24),
                      const Text(
                        "تم اكتشاف تسجيل للشاشة!",
                        style: TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        reason,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        "⚠️ تحذير: هذا المحتوى محمي بحقوق النشر.\nمحاولة تسجيل المحتوى تعرض حسابك للحظر النهائي فوراً.",
                        style: TextStyle(color: AppColors.accentYellow, fontSize: 14, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            if (Platform.isAndroid) {
                              SystemNavigator.pop();
                            } else {
                              exit(0);
                            }
                          },
                          child: const Text("إغلاق التطبيق فوراً", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
      } catch (e) {}
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
      setState(() { _isError = true; _errorMessage = "No video sources"; });
      return;
    }
    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });
    _currentQuality = _sortedQualities.contains("480p") ? "480p" : (_sortedQualities.isNotEmpty ? _sortedQualities.first : "");
    if (_currentQuality.isNotEmpty) _playVideo(widget.streams[_currentQuality]!);
  }

  Future<void> _playVideo(String url, {Duration? startAt}) async {
    if (_isSecurityViolation) return;

    try {
      String playUrl = url;
      if (!url.startsWith('http')) {
        final file = File(url);
        if (!await file.exists()) throw Exception("Offline file missing");
        playUrl = 'http://127.0.0.1:${_proxyService.port}/video?path=${Uri.encodeComponent(file.path)}';
      }
      
      await _player.open(Media(playUrl, httpHeaders: _nativeHeaders), play: false);
      
      if (startAt != null && startAt != Duration.zero) {
        final completer = Completer<void>();
        final subscription = _player.stream.duration.listen((duration) {
          if (duration > Duration.zero && !completer.isCompleted) completer.complete();
        });
        await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => {});
        await subscription.cancel();
        await _player.seek(startAt);
      }

      if (_currentSpeed != 1.0) await _player.setRate(_currentSpeed);
      await _player.play();

    } catch (e) {
      if (mounted && !_isSecurityViolation) {
        setState(() { _isError = true; _errorMessage = "Load Error: $e"; });
      }
    }
  }

  Future<void> _seekRelative(Duration amount) async {
    if (_isSecurityViolation) return;
    try {
      final currentPos = _player.state.position;
      await _player.seek(currentPos + amount);
    } catch (e) {}
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
              onTap: () { Navigator.pop(ctx); _showQualitySelection(); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.gauge, color: Colors.white),
              title: Text("Speed: ${_currentSpeed}x", style: const TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _showSpeedSelection(); },
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

  Future<void> _restoreSystemUI() async {
    // استعادة ظهور شريط الحالة والأزرار السفلية
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    // استعادة وضع الدوران الطبيعي (Portrait + Landscape)
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _watermarkTimer?.cancel();
    _securityFallbackTimer?.cancel();
    _screenProtector.removeListener();
    _proxyService.stop();
    _player.dispose();
    _restoreSystemUI();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSecurityViolation) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final padding = MediaQuery.of(context).viewPadding;
    
    final controlsTheme = MaterialVideoControlsThemeData(
      displaySeekBar: false,
      padding: EdgeInsets.only(
        top: padding.top > 0 ? padding.top : 20, 
        bottom: padding.bottom > 0 ? padding.bottom : 20,
        left: 20, 
        right: 20
      ),
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const SizedBox(width: 10),
        const Expanded(child: MaterialSeekBar()),
        const SizedBox(width: 10),
        MaterialCustomButton(onPressed: _showSettingsSheet, icon: const Icon(LucideIcons.settings, color: Colors.white)),
        const SizedBox(width: 10),
        MaterialCustomButton(
          onPressed: () {
             _restoreSystemUI();
             Navigator.pop(context);
          }, 
          icon: const Icon(LucideIcons.minimize, color: Colors.white)
        ),
      ],
      topButtonBar: [
        MaterialCustomButton(
          onPressed: () {
            _restoreSystemUI();
            Navigator.pop(context);
          }, 
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white)
        ),
        const SizedBox(width: 14),
        Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
      primaryButtonBar: [
        const Spacer(flex: 2),
        MaterialCustomButton(onPressed: () => _seekRelative(const Duration(seconds: -10)), icon: const Icon(Icons.replay_10, size: 36, color: Colors.white)),
        const SizedBox(width: 24),
        const MaterialPlayOrPauseButton(iconSize: 56),
        const SizedBox(width: 24),
        MaterialCustomButton(onPressed: () => _seekRelative(const Duration(seconds: 10)), icon: const Icon(Icons.forward_10, size: 36, color: Colors.white)),
        const Spacer(flex: 2),
      ],
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
    );

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) { 
        if (didPop) _restoreSystemUI(); 
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        primary: false, 
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
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
              Center(
                child: MaterialVideoControlsTheme(
                  normal: controlsTheme,
                  fullscreen: controlsTheme,
                  child: Video(controller: _controller, fit: BoxFit.contain),
                ),
              ),

            if (!_isError && _isInitialized)
              AnimatedAlign(
                duration: const Duration(seconds: 2), 
                curve: Curves.easeInOut,
                alignment: _watermarkAlignment,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      _watermarkText,
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.none),
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
