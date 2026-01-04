import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart'; // تأكد من توليد هذا الملف عبر flutterfire configure
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart'; // استيراد شاشة البداية

void main() async {
  // استخدام Zone لالتقاط الأخطاء في أي مكان بالتطبيق
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // تهيئة Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // تسجيل أخطاء Flutter القاتلة في Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    runApp(const EduVantageApp());
  }, (error, stack) {
    // تسجيل الأخطاء غير المتوقعة (Async errors)
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class EduVantageApp extends StatelessWidget {
  const EduVantageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EduVantage',
      
      // إجبار التطبيق على استخدام الثيم المظلم (Dark Slate) فقط
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, 
      
      // نقطة البداية هي شاشة السبلاش
      home: const SplashScreen(),
    );
  }
}
