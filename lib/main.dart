import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart'; // سيتم توليده
import 'core/theme/app_theme.dart';

void main() async {
  // المنطقة الآمنة لالتقاط الأخطاء في كل خطوة
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // تهيئة Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // تفعيل Crashlytics للأخطاء القاتلة
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    runApp(const EduVantageApp());
  }, (error, stack) {
    // إرسال أي خطأ آخر (Async errors) إلى Crashlytics
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
      
      // تطبيق الثيم المظلم فقط (كما في التصميم)
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, 

      home: const Scaffold(
        body: Center(
          child: CircularProgressIndicator(), // شاشة تحميل مؤقتة
        ),
      ),
    );
  }
}
