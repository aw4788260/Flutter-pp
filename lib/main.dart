import 'dart:async';
import 'dart:ui'; // مطلوب لـ ErrorWidget
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
// استيراد مكتبة FFmpeg (تأكد من أن هذا المسار يطابق المكتبة التي تستخدمها في pubspec.yaml)
// إذا كنت تستخدم ffmpeg_kit_flutter_min_gpl استخدم: package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit_config.dart
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit_config.dart'; 

import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // --------------------------------------------------------
    // 🔥 محاولة تحميل FFmpeg يدوياً لتفادي خطأ JNI (الحل الجديد) 🔥
    // --------------------------------------------------------
    try {
      // هذا السطر يجبر المكتبة على التهيئة المبكرة
      // ignore: deprecated_member_use
      await FFmpegKitConfig.init(); 
      debugPrint("FFmpeg Loaded Successfully via Config!");
    } catch (e) {
      debugPrint("Warning: FFmpeg Manual Init Failed: $e");
      // لن نوقف التطبيق، سنكمل حتى لو فشل التحميل
    }
    // --------------------------------------------------------

    // 1. تفعيل وضع الحماية
    await _enableSecureMode();

    // 2. تهيئة Firebase
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    // 3. تفعيل تسجيل الأخطاء القاتلة
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // إضافة ErrorWidget لتشخيص أي أخطاء في واجهة المستخدم بدلاً من الشاشة الرمادية
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.blueGrey.shade900,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "UI Error: ${details.exception}",
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };

    // تشغيل التطبيق
    runApp(const EduVantageApp());
  }, (error, stack) {
    // تسجيل الأخطاء غير المتوقعة
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

/// دالة تفعيل الحماية الأمنية
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
      home: const SplashScreen(),
    );
  }
}
