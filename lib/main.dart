import 'dart:async'; // ضروري لـ runZonedGuarded
import 'dart:ui';    // ضروري للتحكم في الأخطاء
import 'package:flutter/material.dart'; // المكتبة الأساسية (كانت مفقودة)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// تأكد من أن مسارات ملفاتك صحيحة، قد تحتاج تعديل المسار إذا كان مختلفاً
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 🔥 الكود الكاشف للأخطاء (لحل مشكلة الشاشة البيضاء) 🔥
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // محاولة تسجيل الخطأ في فايربيز
      try {
         FirebaseCrashlytics.instance.recordError(details.exception, details.stack, reason: 'UI Render Error');
      } catch (_) {}

      // شاشة الخطأ الزرقاء
      return Material(
        color: Colors.blueGrey.shade900,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
                const SizedBox(height: 20),
                const Text(
                  "UI BUILD ERROR",
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 24),
                ),
                const SizedBox(height: 20),
                Text(
                  details.exception.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    };
    // 🔥 نهاية الكود 🔥

    runApp(const EduVantageApp());
    
  }, (error, stack) {
    // تسجيل الأخطاء القاتلة
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (_) {
      print(error);
    }
  });
}

class EduVantageApp extends StatelessWidget {
  const EduVantageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EduVantage', // أو اسم تطبيقك
      theme: AppTheme.darkTheme, // تأكد أن AppTheme معرف لديك
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
