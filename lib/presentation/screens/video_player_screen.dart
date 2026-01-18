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

  String _currentQuality = "";
  List<String> _sortedQualities = [];
  double _currentSpeed = 1.0;

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitialized = false;
  
  bool _isDisposing = false;
  
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  final Map<String, String> _serverHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12) ExoPlayerLib/2.18.1',
  };
  final Map<String, String> _youtubeHeaders = {}; 

  @override
  void initState() {
    super.initState();
    _initializePlayerScreen();
  }

  Future<void> _initializePlayerScreen() async {
    FirebaseCrashlytics.instance.log("🎬 MediaKit: Init Started for '${widget.title}'");
    await FirebaseCrashlytics.instance.setCustomKey('video_title', widget.title);

    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      await WakelockPlus.enable();
      await _startProxyServer();

      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024, 
        ),
      );
      
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true, 
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );

      _player.stream.error.listen((error) {
        debugPrint("🚨 MediaKit Stream Error: $error");
        FirebaseCrashlytics.instance.recordError(error, null, reason: 'MediaKit Stream Error');
      });

      _loadUserData();
      _startWatermarkAnimation();

      if (mounted) {
        setState(() {
          _isInitialized = true;
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
      FirebaseCrashlytics.instance.log("✅ Proxy started on port ${_proxyService.port}");
    } catch (e, s) {
      debugPrint("Proxy Error: $e");
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Proxy Start Error');
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
      debugPrint("⚠️ SafeExit Error: $e");
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
      } catch (e) { /* ignore */ }
    }
    if (mounted) {
      setState(() {
        _watermarkText = displayText.isNotEmpty ? displayText : 'User';
      });
    }
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
    if (_isDisposing) return;
    
    FirebaseCrashlytics.instance.log("▶️ _playVideo Called. Quality: $_currentQuality");
    
    try {
      String playUrl = url;
      String? audioUrl; 

      // 1. منطق الأونلاين (Online Split)
      if (url.contains('|')) {
        FirebaseCrashlytics.instance.log("🌐 Detected Online Split Stream");
        final parts = url.split('|');
        playUrl = parts[0];
        if (parts.length > 1) {
          audioUrl = parts[1];
        }
      } 
      // 2. منطق الأونلاين البسيط (Online Simple)
      else if (url.startsWith('http')) {
         FirebaseCrashlytics.instance.log("🌐 Detected Online Simple Stream");
         playUrl = url;
      }
      // 3. منطق الأوفلاين (Offline Encrypted)
      else {
        FirebaseCrashlytics.instance.log("📂 Detected Offline File Path: $url");
        final file = File(url);
        
        if (!await file.exists()) {
           FirebaseCrashlytics.instance.log("❌ Offline file NOT FOUND at: $url");
           throw Exception("Offline file missing");
        }
        
        // ✅ إضافة &ext=.mp4 لمساعدة المشغل (ExoPlayer) على تحديد الحاوية
        playUrl = 'http://127.0.0.1:${_proxyService.port}/video?path=${Uri.encodeComponent(file.path)}&ext=.mp4';
        FirebaseCrashlytics.instance.log("🔗 Generated Video Proxy URL: $playUrl");

        // البحث عن ملف الصوت في قاعدة البيانات
        if (Hive.isBoxOpen('downloads_box')) {
           final box = Hive.box('downloads_box');
           final String absoluteVideoPath = file.absolute.path;
           
           try {
             // البحث عن العنصر الذي يملك نفس مسار الفيديو
             final downloadItem = box.values.firstWhere(
               (item) {
                  if (item['path'] == null) return false;
                  return File(item['path']).absolute.path == absoluteVideoPath;
               }, 
               orElse: () => null
             );

             if (downloadItem != null) {
                FirebaseCrashlytics.instance.log("✅ Hive: Found matching item: ${downloadItem['title']}");
                
                if (downloadItem['audioPath'] != null) {
                    final String audioPath = downloadItem['audioPath'];
                    final File audioFile = File(audioPath);
                    
                    if (await audioFile.exists()) {
                       // ✅ تمرير مسار الصوت للبروكسي مع إضافة &ext=.mp4
                       audioUrl = 'http://127.0.0.1:${_proxyService.port}/video?path=${Uri.encodeComponent(audioFile.path)}&ext=.mp4';
                       FirebaseCrashlytics.instance.log("🔗 Generated Audio Proxy URL: $audioUrl");
                    } else {
                       FirebaseCrashlytics.instance.log("⚠️ Hive: Audio file recorded but missing on disk: $audioPath");
                    }
                } else {
                   FirebaseCrashlytics.instance.log("ℹ️ Hive: No audioPath for this item (Single file)");
                }
             } else {
                FirebaseCrashlytics.instance.log("⚠️ Hive: No item found matching path: $absoluteVideoPath");
             }
           } catch (e) {
             FirebaseCrashlytics.instance.log("❌ Hive Search Error: $e");
           }
        }
      }
      
      await _player.stop();
      
      final bool isYoutubeSource = playUrl.contains('googlevideo.com');
      final headers = isYoutubeSource ? _youtubeHeaders : _serverHeaders;    

      FirebaseCrashlytics.instance.log("🎬 Opening Media...");
      await _player.open(
        Media(playUrl, httpHeaders: headers), 
        play: false
      );

      // دمج الصوت (سواء أونلاين أو أوفلاين)
      if (audioUrl != null) {
        FirebaseCrashlytics.instance.log("🔊 Setting Audio Track...");
        // ✅ تأخير بسيط لضمان تهيئة الفيديو
        await Future.delayed(const Duration(milliseconds: 200));
        
        await _player.setAudioTrack(AudioTrack.uri(
          audioUrl,
          title: "HQ Audio",
          language: "en"
        ));
      }
      
      if (startAt != null && startAt != Duration.zero) {
        int retries = 0;
        while (_player.state.duration == Duration.zero && retries < 50) { // تقليل المحاولات لتجنب التعليق
          if (_isDisposing) return;
          await Future.delayed(const Duration(milliseconds: 100));
          retries++;
        }
        if (_player.state.duration > Duration.zero) {
           await _player.seek(startAt);
        }
      }

      if (_currentSpeed != 1.0) {
        await _player.setRate(_currentSpeed);
      }

      await _player.play();
      FirebaseCrashlytics.instance.log("✅ Playback Started");

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PlayVideo Function Failed');
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
      if (_player.state.duration == Duration.zero) return; 
      final currentPos = _player.state.position;
      await _player.seek(currentPos + amount);
    } catch (e) {/*ignore*/}
  }

  void _showSettingsSheet() {
    if (!mounted) return;
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
    if (!mounted) return;
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
    if (!mounted) return;
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
       _isDisposing = true;
       _watermarkTimer?.cancel();
       _player.dispose(); 
       _proxyService.stop();
       _resetSystemChrome();
       WakelockPlus.disable();
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
                    Text(_errorMessage, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                          FirebaseCrashlytics.instance.log("🔄 User clicked Retry");
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
                  child: Video(
                    controller: _controller,
                    fit: BoxFit.contain, 
                  ),
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
