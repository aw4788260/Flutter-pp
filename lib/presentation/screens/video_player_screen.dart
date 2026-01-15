import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

  // --- Legacy / Manual Stream Switching Variables (للوضع القديم) ---
  String _currentQuality = "";
  List<String> _sortedQualities = [];
  
  // --- Native HLS Track Switching Variables (للوضع الجديد) ---
  List<VideoTrack> _videoTracks = [];
  VideoTrack _selectedVideoTrack = VideoTrack.auto();

  double _currentSpeed = 1.0;

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitialized = false;
  
  bool _isDisposing = false;
  
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  final Map<String, String> _nativeHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12) ExoPlayerLib/2.18.1',
  };

  @override
  void initState() {
    super.initState();
    _initializePlayerScreen();
  }

  Future<void> _initializePlayerScreen() async {
    FirebaseCrashlytics.instance.log("🎬 MediaKit Player: Init Sequence Started");

    try {
      // 1. إعدادات الشاشة والنظام
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await WakelockPlus.enable();

      // 2. تشغيل البروكسي المحلي (للملفات المحملة)
      await _startProxyServer();

      // 3. تهيئة المشغل
      _player = Player();
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );

      // مراقبة الأخطاء
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

      // ✅ استماع للمسارات (Tracks) لدعم الجودات المتعددة في رابط واحد (HLS)
      _player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() {
            _videoTracks = tracks.video;
          });
        }
      });

      // ✅ استماع للمسار المختار حالياً لتحديث الواجهة
      _player.stream.track.listen((track) {
        if (mounted) {
          setState(() {
            _selectedVideoTrack = track.video;
          });
        }
      });

      _loadUserData();
      _startWatermarkAnimation();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _parseQualitiesAndPlay();
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

  Future<void> _resetSystemChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;
    _isDisposing = true;

    try {
      _watermarkTimer?.cancel();
      await _player.stop(); 
      await _player.dispose(); 
      _proxyService.stop(); 
      await _resetSystemChrome();
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint("⚠️ Error during safe exit: $e");
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
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
      if (_isDisposing) { timer.cancel(); return; }
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

  void _parseQualitiesAndPlay() {
    if (widget.streams.isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = "No video sources available";
      });
      return;
    }

    // المنطق القديم: ترتيب الروابط اليدوية (للاستخدام كاحتياطي)
    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    // نختار الجودة الافتراضية للبدء
    // إذا كان الرابط ماستر (مثل "Auto")، فهذا هو المطلوب.
    _currentQuality = _sortedQualities.contains("480p") 
        ? "480p" 
        : (_sortedQualities.isNotEmpty ? _sortedQualities.first : "");

    if (_currentQuality.isNotEmpty) {
      _playVideo(widget.streams[_currentQuality]!);
    }
  }

  Future<void> _playVideo(String url, {Duration? startAt}) async {
    if (_isDisposing) return;
    try {
      String playUrl = url;

      if (!url.startsWith('http')) {
        final file = File(url);
        if (!await file.exists()) throw Exception("Offline file missing");
        playUrl = 'http://127.0.0.1:${_proxyService.port}/video?path=${Uri.encodeComponent(file.path)}';
      }
      
      // إيقاف السابق وفتح الجديد
      // ✅ ملاحظة: عند استخدام HLS Master، لن نحتاج لاستدعاء هذه الدالة مرة أخرى لتغيير الجودة
      await _player.stop();
      await _player.open(Media(playUrl, httpHeaders: _nativeHeaders), play: false);
      
      if (startAt != null && startAt != Duration.zero) {
        // محاولة القفز للتوقيت (مع انتظار تحميل الميتا داتا)
        int retries = 0;
        while (_player.state.duration == Duration.zero && retries < 40) {
          if (_isDisposing) return;
          await Future.delayed(const Duration(milliseconds: 100));
          retries++;
        }
        await _player.seek(startAt);
      }

      if (_currentSpeed != 1.0) {
        await _player.setRate(_currentSpeed);
      }

      await _player.play();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Play Failed');
      if (mounted && !_isDisposing) {
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

  // دالة مساعدة للحصول على اسم الجودة من المسار
  String _getVideoTrackName(VideoTrack track) {
    if (track == VideoTrack.auto()) return "Auto";
    if (track == VideoTrack.no()) return "None";
    if (track.h != null && track.h! > 0) return "${track.h}p";
    if (track.w != null && track.w! > 0) return "${track.w}p";
    return track.title ?? "Unknown";
  }

  void _showSettingsSheet() {
    // تحديد النص المعروض للجودة
    String qualityText = _currentQuality;
    
    // إذا كان لدينا مسارات HLS حقيقية، نعرض اسم المسار المختار من المشغل
    // نعتبر أن المسارات حقيقية إذا كان هناك أكثر من مجرد auto/no
    bool hasNativeTracks = _videoTracks.any((t) => t.w != null && t.h != null);
    if (hasNativeTracks) {
        qualityText = _getVideoTrackName(_selectedVideoTrack);
    }

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
              title: Text("Quality: $qualityText", style: const TextStyle(color: Colors.white)),
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
    // 1. تصفية المسارات الصالحة (نستبعد 'no' ونرتب الباقي)
    final meaningfulTracks = _videoTracks.where((t) => t != VideoTrack.no()).toList();
    
    // ترتيب: Auto أولاً، ثم الجودات من الأعلى للأسفل
    meaningfulTracks.sort((a, b) {
       if (a == VideoTrack.auto()) return -1;
       if (b == VideoTrack.auto()) return 1;
       return (b.h ?? 0).compareTo(a.h ?? 0);
    });

    // هل نستخدم نظام المسارات الذكي (HLS) أم الروابط اليدوية؟
    // نستخدم HLS إذا كان لدينا مسارات متعددة (أكثر من مجرد Auto)
    bool useNativeTracks = meaningfulTracks.length > 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: useNativeTracks 
          ? // --- خيارات HLS Native (الحل الجديد) ---
            meaningfulTracks.map((track) {
              final name = _getVideoTrackName(track);
              final isSelected = _selectedVideoTrack == track;
              return ListTile(
                title: Text(name, style: TextStyle(color: isSelected ? AppColors.accentYellow : Colors.white)),
                trailing: isSelected ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _player.setVideoTrack(track); // ✅ تغيير الجودة فورياً بدون إعادة تحميل
                },
              );
            }).toList()
          : // --- خيارات الروابط اليدوية (الحل القديم/الاحتياطي) ---
            _sortedQualities.reversed.map((q) => ListTile(
              title: Text(q, style: TextStyle(color: q == _currentQuality ? AppColors.accentYellow : Colors.white)),
              trailing: q == _currentQuality ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
              onTap: () {
                Navigator.pop(ctx);
                if (q != _currentQuality) {
                  final currentPos = _player.state.position;
                  setState(() { _currentQuality = q; _isError = false; });
                  _playVideo(widget.streams[q]!, startAt: currentPos); // ⚠️ إعادة تحميل
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
    if (!_isDisposing) {
       _player.dispose(); 
       _proxyService.stop();
       _resetSystemChrome();
       WakelockPlus.disable();
       _watermarkTimer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        MaterialCustomButton(
          onPressed: _showSettingsSheet,
          icon: const Icon(LucideIcons.settings, color: Colors.white),
        ),
        const SizedBox(width: 10),
        MaterialCustomButton(
          onPressed: () {
            _safeExit();
          },
          icon: const Icon(LucideIcons.minimize, color: Colors.white),
        ),
      ],
      topButtonBar: [
        MaterialCustomButton(
          onPressed: () {
            _safeExit();
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
    );

    return PopScope(
      canPop: false, 
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _safeExit(); 
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
                          // إعادة المحاولة بالرابط الحالي
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
                  child: Video(
                    controller: _controller,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6), 
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _watermarkText,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85), 
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
