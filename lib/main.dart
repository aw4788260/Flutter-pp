import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
// import 'firebase_options.dart'; // ❌ تم إيقافه كما طلبت للاعتماد على google-services.json مباشرة
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. تفعيل وضع الحماية (منع لقطات الشاشة وتسجيل الفيديو)
    await _enableSecureMode();

    // 2. تهيئة Firebase
    // نتحقق أولاً إذا كان التطبيق مهيأً مسبقاً لتجنب أخطاء DuplicateApp
    if (Firebase.apps.isEmpty) {
      // التهيئة بدون options تجعل التطبيق يقرأ الإعدادات تلقائياً من ملف:
      // android/app/google-services.json (للأندرويد)
      // ios/Runner/GoogleService-Info.plist (للايفون)
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
      title: 'MeD O7aS Pro', // الاسم الظاهر في التطبيق
      theme: AppTheme.darkTheme, // الثيم المطابق لـ Gunmetal
      themeMode: ThemeMode.dark,
      home: const SplashScreen(), // نقطة البداية (Splash -> Login -> Home)
    );
  }
}
