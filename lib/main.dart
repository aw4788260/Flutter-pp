import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    // 1. التأكد من تهيئة روابط فلاتر مع النظام الأساسي
    WidgetsFlutterBinding.ensureInitialized();

    // 2. ✅ حل مشكلة الشاشة السوداء مع FFmpeg:
    // نقوم بتشغيل واجهة بسيطة جداً (فارغة بنفس لون الخلفية) لإعطاء النظام 
    // وقتاً لتحميل مكتبات الـ Native الثقيلة الخاصة بـ FFmpeg في الخلفية.
    await Future.delayed(const Duration(milliseconds: 500));

    // 3. تهيئة Hive وفتح الصناديق
    await Hive.initFlutter();
    await Hive.openBox('auth_box');
    await Hive.openBox('app_cache');
    await Hive.openBox('downloads_box');

    // 4. تفعيل وضع الحماية
    await _enableSecureMode();

    // 5. تهيئة Firebase
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    // 6. تسجيل الأخطاء
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    runApp(const EduVantageApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

Future<void> _enableSecureMode() async {
  try {
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
      // تأكد أن الشاشة التالية (SplashScreen) لا تقوم بعمليات ثقيلة في الـ initState
      home: const SplashScreen(), 
    );
  }
}
