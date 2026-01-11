import 'dart:async';
import 'dart:io';
import 'dart:math'; // مهم للعلامة المائية
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ✅ استيراد مكتبات المشغل الجديد
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

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams; // الجودات المتاحة
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

  // ✅ الهيدر السحري: لضمان قبول يوتيوب للاتصال (ExoPlayer Identity)
  final Map<String, String> _nativeHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12) ExoPlayerLib/2.18.1',
  };

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("🎬 MediaKit Player: Init Started");

    // 1. إنشاء المشغل (Player)
    _player = Player();

    // 2. إعداد وحدة التحكم بالعرض (VideoController)
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true, // تفعيل تسريع الهاردوير للأداء العالي
        androidAttachSurfaceAfterVideoOutput: true, // حل لمشاكل الشاشة السوداء في بعض أجهزة سامسونج/شاومي
      ),
    );

    // 3. الاستماع للأخطاء وتسجيلها
    _player.stream.error.listen((error) {
      FirebaseCrashlytics.instance.log("🚨 MediaKit Stream Error: $error");
      FirebaseCrashlytics.instance.recordError(
          Exception(error), null,
          reason: 'MediaKit Playback Error');

      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "Playback Error: $error";
        });
      }
    });

    // 4. الاستماع لانتهاء الفيديو (اختياري)
    _player.stream.completed.listen((completed) {
      if (completed) {
        FirebaseCrashlytics.instance.log("✅ Video Completed");
      }
    });

    // بدء الوظائف الأخرى
    _setupScreenProtection();
    _loadUserData();
    _startWatermarkAnimation();
    _parseQualities();
  }

  Future<void> _setupScreenProtection() async {
    try {
      // إجبار الوضع الأفقي
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      
      // منع إغلاق الشاشة
      await WakelockPlus.enable();
      
      // تفعيل حماية المحتوى (شاشة سوداء عند التسجيل)
      await ScreenProtector.protectDataLeakageOn();
      await ScreenProtector.preventScreenshotOn();

      // مراقب إضافي
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
                Navigator.pop(context); // إغلاق الحوار
                Navigator.pop(context); // الخروج من الشاشة
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
    } catch (e) {
      FirebaseCrashlytics.instance.log("⚠️ Hive Load Error: $e");
    }
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          // توليد إحداثيات عشوائية للمحاذاة (-1.0 إلى 1.0)
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
      FirebaseCrashlytics.instance.log("❌ Error: No streams provided");
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    // ترتيب الجودات (الأرقام)
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    // اختيار جودة افتراضية (480p أو الأقل لضمان العمل السريع)
    _currentQuality = _sortedQualities.contains("480p")
        ? "480p"
        : (_sortedQualities.isNotEmpty ? _sortedQualities.first : "");

    if (_currentQuality.isNotEmpty) {
      _playVideo(widget.streams[_currentQuality]!);
    }
  }

  Future<void> _playVideo(String url) async {
    try {
      FirebaseCrashlytics.instance.log("🎬 Loading Video URL: $url");

      // ============================================================
      // 1️⃣ السيناريو الأول: ملف أوفلاين (مشفر)
      // ============================================================
      if (!url.startsWith('http')) {
        setState(() => _isDecrypting = true);

        final encryptedFile = File(url);
        if (await encryptedFile.exists()) {
          final tempDir = await getTemporaryDirectory();
          // اسم ملف فريد لتجنب التضارب
          final tempPath = '${tempDir.path}/play_${DateTime.now().millisecondsSinceEpoch}.mp4';

          FirebaseCrashlytics.instance.log("🔓 Decrypting file to: $tempPath");
          
          // فك التشفير باستخدام دالتك المساعدة
          _tempDecryptedFile = await EncryptionHelper.decryptFile(encryptedFile, tempPath);

          // ✅ تشغيل الملف المحلي بـ MediaKit
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
        // ✅ MediaKit يقبل الهيدرز في كائن Media مباشرة
        await _player.open(Media(
          url,
          httpHeaders: _nativeHeaders, // الهيدر الذي يخدع يوتيوب
        ));
      }
      
      // بدء التشغيل
      await _player.play();

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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16), 
              child: Text("Select Quality", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
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
                    _isError = false;
                  });
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

    // ✅ تنظيف MediaKit (مهم جداً لتحرير الذاكرة)
    _player.dispose();

    // حذف الملف المؤقت (تنظيف الكاش)
    if (_tempDecryptedFile != null) {
      try {
        if (_tempDecryptedFile!.existsSync()) _tempDecryptedFile!.deleteSync();
      } catch (e) {
        FirebaseCrashlytics.instance.log("⚠️ Failed to delete temp file: $e");
      }
    }

    // إيقاف الحماية وإعادة التوجيه
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
                      Text(
                        _errorMessage, 
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
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
                          Text("Preparing Offline Video...", style: TextStyle(color: Colors.white70)),
                        ],
                      )
                    // ✅ واجهة العرض الخاصة بـ MediaKit
                    : Video(
                        controller: _controller,
                        // MaterialVideoControls توفر واجهة جاهزة وجميلة (شريط تمرير، صوت، تكبير)
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
                      color: Colors.white.withOpacity(0.4),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),

          // 3. زر الرجوع والعنوان (Custom UI Overlay)
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
