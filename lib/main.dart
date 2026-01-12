import 'dart:async';
import 'dart:io'; // للخروج من التطبيق exit(0)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:safe_device/safe_device.dart'; // ✅ فحص الروت
import 'package:lucide_icons/lucide_icons.dart'; // ✅ أيقونات التنبيه

import 'core/services/notification_service.dart'; 
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

// ✅ مفتاح عام للتحكم في النوافذ من أي مكان
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. تهيئة MediaKit
    MediaKit.ensureInitialized();

    // 2. تهيئة الإشعارات
    await NotificationService().init();

    // 3. تهيئة خدمة الخلفية
    await initializeService();

    // 4. إعدادات النظام
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // 5. الحماية من تصوير الشاشة
    await _enableSecureMode();

    // 6. Firebase
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // 🛡️ 7. تشغيل الحماية (فوري + دوري)
    SecurityManager.instance.checkSecurity();
    SecurityManager.instance.startPeriodicCheck();

    runApp(const EduVantageApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

// =========================================================
// 🛡️ كلاس إدارة الحماية (Security Manager)
// =========================================================
class SecurityManager {
  static final SecurityManager instance = SecurityManager._internal();
  SecurityManager._internal();

  bool _isAlertVisible = false;

  // دالة الفحص
  Future<void> checkSecurity() async {
    if (_isAlertVisible) return;

    try {
      // فحص الحالات
      bool isJailBroken = await SafeDevice.isJailBroken;
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;

      // إذا وُجد أي تهديد
      if (isJailBroken || isDevMode) {
        _isAlertVisible = true;
        _showBlockDialog(isJailBroken, isDevMode);
      }
    } catch (e) {
      debugPrint("Security Check Error: $e");
    }
  }

  // الفحص الدوري
  void startPeriodicCheck() {
    Timer.periodic(const Duration(seconds: 3), (timer) {
      checkSecurity();
    });
  }

  // ✅ عرض نافذة الحظر مع توضيح السبب
  void _showBlockDialog(bool isRoot, bool isDev) {
    // بناء نص الرسالة بناءً على السبب المكتشف
    String arabicReason = "";
    String englishReason = "";

    if (isRoot) {
      arabicReason += "• تم اكتشاف كسر حماية (Root/Jailbreak)\n";
      englishReason += "• Root/Jailbreak Detected\n";
    }
    if (isDev) {
      arabicReason += "• خيارات المطور مفعلة (Developer Options)\n";
      englishReason += "• Developer Options Enabled\n";
    }

    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF242F3D), // خلفية داكنة
            title: const Row(
              children: [
                Icon(LucideIcons.shieldAlert, color: Color(0xFFEF4444)), // لون أحمر
                SizedBox(width: 10),
                Text("تنبيه أمني / Security Alert", style: TextStyle(color: Color(0xFFEF4444), fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "لا يمكن تشغيل التطبيق لوجود مخاطر أمنية:",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 8),
                  // ✅ عرض السبب بالعربية
                  Text(
                    arabicReason,
                    style: const TextStyle(color: Color(0xFFE1AD01), fontSize: 13), // لون أصفر للسبب
                    textAlign: TextAlign.right,
                  ),
                  const Divider(color: Colors.white24),
                  const Text(
                    "The app cannot run due to security risks:",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  // ✅ عرض السبب بالإنجليزية
                  Text(
                    englishReason,
                    style: const TextStyle(color: Color(0xFFE1AD01), fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "يرجى تعطيل هذه الخيارات للمتابعة.\nPlease disable these settings to continue.",
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                    textAlign: TextAlign.center,
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
      exit(0); // إغلاق فوري إذا لم تكن الواجهة جاهزة
    }
  }
}

// =========================================================
// ⚙️ إعدادات خدمة الخلفية
// =========================================================
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
    await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  } catch (e) {
    debugPrint("Security Mode Error: $e");
  }
}

// =========================================================
// 📱 واجهة التطبيق
// =========================================================
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
