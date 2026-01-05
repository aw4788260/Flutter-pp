import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart'; // ✅ استخدام النسخة الحديثة لحل مشكلة البناء
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  // استخدام runZonedGuarded لالتقاط كافة الأخطاء وإرسالها لـ Crashlytics
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ تفعيل حماية تصوير الشاشة فوراً عند تشغيل التطبيق لتجنب أي ثغرات
    await _enableSecureMode();

    // تهيئة Firebase بناءً على الإعدادات التي تم إنشاؤها
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // تسجيل أخطاء فلاتر في Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    runApp(const EduVantageApp());
  }, (error, stack) {
    // تسجيل الأخطاء الخارجة عن نطاق فلاتر
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

/// دالة تمنع تصوير الشاشة أو تسجيل الفيديو (Android فقط) باستخدام الإصدار Plus
Future<void> _enableSecureMode() async {
  try {
    // تفعيل خاصية FLAG_SECURE لمنع لقطات الشاشة وتسجيل الشاشة
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
      title: 'EduVantage',
      theme: AppTheme.darkTheme, // تطبيق الثيم الداكن المخصص
      themeMode: ThemeMode.dark,
      home: const SplashScreen(), // شاشة البداية (Splash)
    );
  }
}
