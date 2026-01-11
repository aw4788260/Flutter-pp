import 'dart:async';
import 'dart:io';
import 'dart:math'; // ضروري للعلامة المائية
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';       // ✅ محرك التشغيل الجديد
import 'package:media_kit_video/media_kit_video.dart'; // ✅ واجهة العرض
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_protector/screen_protector.dart'; 
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 
import '../../core/constants/app_colors.dart';
import '../../core/utils/encryption_helper.dart'; 

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

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // ✅ متغيرات MediaKit
  late final Player _player;
  late final VideoController _controller;
  
  String _currentQuality = "";
  List<String> _sortedQualities = [];
  
  // حالات التحميل والخطأ
  bool _isError = false;
  String _errorMessage = "";
  bool _isDecrypting = false; 
  File? _tempDecryptedFile;

  // العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  Timer? _screenRecordingTimer;

  // ✅ الهيدر السحري: لضمان قبول يوتيوب للاتصال
  final Map<String, String> _nativeHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12) ExoPlayerLib/2.18.1',
  };

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("🎬 MediaKit Player: Init Started");

    // 1. إنشاء المشغل والتحكم
    _player = Player();
    
    _controller = VideoController(_player, configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true, // تفعيل تسريع الهاردوير
      androidAttachSurfaceAfterVideoOutput: true, // حل مشاكل الشاشة السوداء
    ));

    // 2. تسجيل الأخطاء القادمة من المشغل
    _player.stream.error.listen((error) {
      FirebaseCrashlytics.instance.log("🚨 MediaKit Error: $error");
      // تسجيل استثناء غير قاتل في Crashlytics للمتابعة
      FirebaseCrashlytics.instance.recordError(Exception(error), null, reason: 'MediaKit Stream Error');
      
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "Playback Error: $error";
        });
      }
    });

    // 3. الإعدادات الأخرى
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

  Future<void> _playVideo(String url) async {
    try {
      FirebaseCrashlytics.instance.log("🎬 Loading Video: $url");

      // ============================================================
      // 1️⃣ السيناريو الأول: ملف أوفلاين (مشفر)
      // ============================================================
      if (!url.startsWith('http')) {
        setState(() => _isDecrypting = true); 

        final encryptedFile = File(url);
        if (await encryptedFile.exists()) {
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/play_${DateTime.now().millisecondsSinceEpoch}.mp4';
          
          FirebaseCrashlytics.instance.log("🔓 Decrypting file to: $tempPath");
          _tempDecryptedFile = await EncryptionHelper.decryptFile(encryptedFile, tempPath);
          
          // ✅ تشغيل الملف المحلي
          await _player.open(Media(_tempDecryptedFile!.path));
        } else {
          throw Exception("Offline file missing at path: $url");
        }
        
        setState(() => _isDecrypting = false);
      } 
      // ============================================================
      // 2️⃣ السيناريو الثاني: أونلاين (يوتيوب HLS)
      // ============================================================
      else {
        // ✅ تشغيل الرابط مع تمرير الهيدرز لخداع السيرفر
        await _player.open(Media(
          url,
          httpHeaders: _nativeHeaders, 
        ));
      }
      
      _player.play();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'MediaKit Load Failed: $url');
      if (mounted) {
        setState(() {
          _isError = true;
          _isDecrypting = false;
          _errorMessage = "Failed to load video.";
        });
      }
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
                  setState(() { _currentQuality = q; _isError = false; });
                  _playVideo(widget.streams[q]!);
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
    _watermarkTimer?.cancel();
    _screenRecordingTimer?.cancel();
    
    // ✅ إيقاف وتنظيف المشغل (مهم جداً لتحرير الذاكرة)
    _player.dispose();

    // حذف الملف المؤقت عند الخروج
    if (_tempDecryptedFile != null) {
      try {
        if (_tempDecryptedFile!.existsSync()) _tempDecryptedFile!.deleteSync();
      } catch (_) {}
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
          // 1. المشغل (MediaKit Video Widget)
          Center(
            child: _isError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
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
                  )
                : (_isDecrypting)
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          CircularProgressIndicator(color: AppColors.accentYellow),
                          SizedBox(height: 16),
                          Text("Preparing Video...", style: TextStyle(color: Colors.white70)),
                        ],
                      )
                    : Video(
                        controller: _controller,
                        // استخدام واجهة التحكم الجاهزة والجميلة (تشبه يوتيوب/نتفليكس)
                        controls: MaterialVideoControls, 
                      ),
          ),

          // 2. العلامة المائية المتحركة
          if (!_isError && !_isDecrypting)
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
                  
                  // زر تغيير الجودة (اختياري)
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _showQualitySheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(LucideIcons.settings, color: Colors.white, size: 16),
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
