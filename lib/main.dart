import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ ضروري للتحكم في SystemChrome
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:media_kit/media_kit.dart'; // ✅ (1) إضافة استيراد MediaKit
// import 'firebase_options.dart'; // ❌ تم إيقافه
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ (2) تهيئة MediaKit (ضروري جداً قبل التشغيل)
    MediaKit.ensureInitialized();

    // ✅ (3) ضبط وضع الشاشة الأساسي عند بدء التطبيق
    // هذا يضمن أن أشرطة النظام (الساعة والبطارية والأزرار السفلية) ظاهرة وبحجمها الطبيعي
    // مما يمنع مشكلة الإزاحة التي تحدثت عنها
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
    // نتحقق أولاً إذا كان التطبيق مهيأً مسبقاً لتجنب أخطاء DuplicateApp
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
