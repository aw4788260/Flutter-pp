import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ ضروري للتحكم في SystemChrome
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:media_kit/media_kit.dart'; // ✅ (1) إضافة استيراد MediaKit
// ✅ استيرادات خدمة الخلفية والإشعارات
import 'package:flutter_background_service/flutter_background_service.dart';
import 'core/services/notification_service.dart'; 
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ (2) تهيئة MediaKit (ضروري جداً قبل التشغيل)
    MediaKit.ensureInitialized();

    // ✅ (3) تهيئة الإشعارات (الجديد)
    await NotificationService().init();

    // ✅ (4) تهيئة وتشغيل خدمة الخلفية (الجديد)
    await initializeService();

    // ✅ (5) ضبط وضع الشاشة الأساسي عند بدء التطبيق
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // 1. تفعيل وضع الحماية (منع لقطات الشاشة وتسجيل الفيديو)
    await _enableSecureMode();

    // 2. تهيئة Firebase
    if (Firebase.apps.isEmpty) {
      // التهيئة بدون options تجعل التطبيق يقرأ الإعدادات تلقائياً من ملف google-services.json
      await Firebase.initializeApp();
    }

    // 3. تفعيل تسجيل الأخطاء القاتلة في Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // تشغيل التطبيق
    runApp(const EduVantageApp());
  }, (error, stack) {
    // تسجيل الأخطاء غير المتوقعة (Async Errors)
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

/// ✅ دالة إعداد خدمة الخلفية
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // الدالة التي ستعمل في الخلفية
      autoStart: true, // تشغيل تلقائي مع التطبيق
      isForegroundMode: true, // وضع Foregound لمنع النظام من قتل التطبيق
      notificationChannelId: 'downloads_channel', // نفس القناة المعرفة في NotificationService
      initialNotificationTitle: 'مــــداد Service',
      initialNotificationContent: 'Running in background to keep downloads active',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

/// ✅ دالة نقطة الدخول للخدمة (يجب أن تكون خارج الكلاس أو static)
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // هذه الدالة تبقي التطبيق "نشطاً" في نظر النظام
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
}

/// ✅ دالة الخلفية لنظام iOS (مطلوبة للتهيئة)
@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

/// دالة تفعيل الحماية الأمنية
Future<void> _enableSecureMode() async {
  try {
    // FLAG_SECURE يمنع ظهور محتوى التطبيق في الـ Recent Apps ويمنع لقطات الشاشة
    await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  } catch (e) {
    debugPrint("Security Mode Error: $e");
  }
}

class EduVantageApp extends StatelessWidget {
  const EduVantageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مــــداد', // الاسم الظاهر في التطبيق
      theme: AppTheme.darkTheme, // الثيم المطابق لـ Gunmetal
      themeMode: ThemeMode.dark,
      home: const SplashScreen(), // نقطة البداية (Splash -> Login -> Home)
    );
  }
}
