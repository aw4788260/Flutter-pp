import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:hive_flutter/hive_flutter.dart'; // ✅ إضافة استيراد Hive
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    // 1. ضمان استقرار إطارات العمل
    WidgetsFlutterBinding.ensureInitialized();

    // 2. تفعيل وضع الحماية (منع لقطات الشاشة وتسجيل الفيديو)
    await _enableSecureMode();

    // 3. ✅ تهيئة Hive وفتح الصناديق الأساسية هنا (لحل مشكلة الشاشة السوداء)
    await Hive.initFlutter();
    await Hive.openBox('auth_box');    // لتخزين بيانات تسجيل الدخول والجلسة
    await Hive.openBox('app_cache');   // لتخزين بيانات Init Data للعمل أوفلاين
    await Hive.openBox('downloads_box'); // لإدارة الملفات المحملة

    // 4. تهيئة Firebase
    if (Firebase.apps.isEmpty) {
      // الاعتماد على ملفات الإعدادات التلقائية (google-services.json)
      await Firebase.initializeApp();
    }

    // 5. تفعيل تسجيل الأخطاء القاتلة في Crashlytics
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
