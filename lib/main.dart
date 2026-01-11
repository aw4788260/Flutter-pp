import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui'; // ضروري لـ PlatformDispatcher
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. تفعيل وضع الحماية (منع لقطات الشاشة وتسجيل الفيديو)
    await _enableSecureMode();

    // 2. تهيئة Firebase باستخدام الإعدادات التلقائية
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    // 3. ✅ تسجيل الأخطاء القاتلة (التي تسبب انهيار التطبيق فوراً)
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // 4. ✅ تسجيل جميع الأخطاء غير القاتلة التي تحدث داخل إطار عمل فلاتر
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      return true;
    };

    runApp(const EduVantageApp());
  }, (error, stack) {
    // 5. ✅ تسجيل الأخطاء غير المتوقعة والبرمجية (Async Errors) كأخطاء قاتلة
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

/// دالة تفعيل الحماية الأمنية
Future<void> _enableSecureMode() async {
  try {
    // يمنع ظهور محتوى التطبيق في القائمة الأخيرة ويمنع تصوير الشاشة
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
      title: 'مــــداد',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
