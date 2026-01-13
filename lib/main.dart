import 'dart:async';
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:safe_device/safe_device.dart'; 
import 'package:screen_protector/screen_protector.dart'; 
import 'package:lucide_icons/lucide_icons.dart'; 
// ✅ 1. استيراد مكتبة الصوت
import 'package:audio_session/audio_session.dart'; 

import 'core/services/notification_service.dart'; 
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    MediaKit.ensureInitialized();

    // ✅ 2. إعداد جلسة الصوت (تم التصحيح)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.movie,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
        // ❌ تم حذف المعامل الخاطئ من هنا
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    // ✅ 3. منع تسجيل الصوت باستخدام AndroidAudioManager مباشرة
    if (Platform.isAndroid) {
      try {
        // استخدام الاسم الصحيح للـ Enum: AndroidAudioCapturePolicy.allowNone
        await AndroidAudioManager().setAllowedCapturePolicy(AndroidAudioCapturePolicy.allowNone);
      } catch (e) {
        debugPrint("Error setting audio capture policy: $e");
      }
    }

    await NotificationService().init();
    await initializeService();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    await _enableSecureMode();

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // تشغيل الحماية
    SecurityManager.instance.initListeners(); 
    SecurityManager.instance.checkSecurity();
    SecurityManager.instance.startPeriodicCheck();

    runApp(const EduVantageApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

// ... (باقي الكلاسات SecurityManager و EduVantageApp تبقى كما هي تماماً) ...
// =========================================================
// 🛡️ كلاس إدارة الحماية (Security Manager)
// =========================================================
class SecurityManager {
  static final SecurityManager instance = SecurityManager._internal();
  SecurityManager._internal();

  bool _isAlertVisible = false;
  
  // كاشف للحالة لاستخدامه في Splash Screen لمنع الانتقال
  bool get isBlocked => _isAlertVisible;

  // دالة تهيئة المستمعين (Screen Recording Listener)
  void initListeners() {
    ScreenProtector.addListener(() {
      // عند بدء التسجيل أو أخذ لقطة شاشة
      checkSecurity();
    }, (isCapturing) {
      if (isCapturing) checkSecurity();
    });
  }

  // دالة الفحص الموحدة
  Future<bool> checkSecurity() async {
    // إذا كانت النافذة ظاهرة بالفعل، نعتبره غير آمن
    if (_isAlertVisible) return false;

    try {
      // 1. فحص الروت وخيارات المطور
      bool isJailBroken = await SafeDevice.isJailBroken;
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
      
      // 2. فحص تسجيل الشاشة
      bool isRecording = await ScreenProtector.isRecording();

      if (isJailBroken || isDevMode || isRecording) {
        _isAlertVisible = true;
        _showBlockDialog(isJailBroken, isDevMode, isRecording);
        return false; // غير آمن
      }
    } catch (e) {
      debugPrint("Security Check Error: $e");
    }
    
    return true; // آمن
  }

  void startPeriodicCheck() {
    // تقليل الوقت لثانية واحدة لزيادة سرعة الكشف
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      await checkSecurity();
    });
  }

  // عرض نافذة الحظر مع الأسباب المختلفة
  void _showBlockDialog(bool isRoot, bool isDev, bool isRecording) {
    String arabicReason = "";
    String englishReason = "";

    // تخصيص الرسالة حسب السبب
    if (isRecording) {
      arabicReason += "• تم اكتشاف تسجيل للشاشة! (مخالفة جسيمة)\n";
      englishReason += "• Screen Recording Detected!\n";
    }
    if (isRoot) {
      arabicReason += "• تم اكتشاف كسر حماية (Root/Jailbreak)\n";
      englishReason += "• Root/Jailbreak Detected\n";
    }
    if (isDev) {
      arabicReason += "• خيارات المطور مفعلة (Developer Options)\n";
      englishReason += "• Developer Options Enabled\n";
    }

    // رسالة التهديد الخاصة بالتسجيل
    String warningMessage = isRecording 
        ? "\n⚠️ تحذير: محاولة تسجيل المحتوى تعرض حسابك للحظر النهائي فوراً."
        : "\nيرجى تعطيل هذه الخيارات للمتابعة.";

    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        useRootNavigator: true, // جعل النافذة فوق كل شيء (Root Navigator)
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF242F3D),
            title: const Row(
              children: [
                Icon(LucideIcons.shieldAlert, color: Color(0xFFEF4444)),
                SizedBox(width: 10),
                Text("Security Alert / تنبيه أمني", style: TextStyle(color: Color(0xFFEF4444), fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end, // محاذاة لليمين للنص العربي
                children: [
                  const Text(
                    "تم إيقاف التطبيق لأسباب أمنية:",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    arabicReason,
                    style: const TextStyle(color: Color(0xFFE1AD01), fontSize: 13, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl, // اتجاه النص
                  ),
                  const Divider(color: Colors.white24),
                  Align( // محاذاة اليسار للإنجليزي
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Action Required:",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          englishReason,
                          style: const TextStyle(color: Color(0xFFE1AD01), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      warningMessage,
                      style: TextStyle(
                        color: isRecording ? const Color(0xFFEF4444) : Colors.white54, // لون أحمر للتهديد
                        fontSize: 12, 
                        fontWeight: FontWeight.bold
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444).withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => exit(0), // إغلاق التطبيق
                  child: const Text("إغلاق التطبيق / EXIT", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      exit(0);
    }
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'downloads_channel',
      initialNotificationTitle: 'مــــداد',
      initialNotificationContent: 'Initializing downloads...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  Timer? watchdogTimer;

  void resetWatchdog() {
    watchdogTimer?.cancel();
    watchdogTimer = Timer(const Duration(seconds: 10), () {
      service.stopSelf();
    });
  }

  resetWatchdog();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('keepAlive').listen((event) {
    resetWatchdog();
  });
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

Future<void> _enableSecureMode() async {
  try {
    // هذا يمنع أخذ لقطات الشاشة (Screenshots) ويظهر شاشة سوداء في التسجيل
    await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  } catch (e) {
    debugPrint("Security Mode Error: $e");
  }
}

class EduVantageApp extends StatefulWidget {
  const EduVantageApp({super.key});

  @override
  State<EduVantageApp> createState() => _EduVantageAppState();
}

class _EduVantageAppState extends State<EduVantageApp> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SecurityManager.instance.checkSecurity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      title: 'مــــداد',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
