import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // للقنوات
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ 1. تفعيل حماية تصوير الشاشة فوراً عند البدء
    await _enableSecureMode();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    runApp(const EduVantageApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

// دالة تمنع تصوير الشاشة (Android)
Future<void> _enableSecureMode() async {
  try {
    // نستخدم القناة المباشرة للأندرويد لفرض FLAG_SECURE
    // تأكد من إضافة مكتبة flutter_windowmanager في pubspec.yaml:
    // flutter_windowmanager: ^0.2.0
    const platform = MethodChannel('flutter_windowmanager');
    await platform.invokeMethod('addFlags', {'flags': 8192}); // 8192 = FLAG_SECURE
  } catch (e) {
    print("Security Mode Error: $e");
  }
}

class EduVantageApp extends StatelessWidget {
  const EduVantageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EduVantage',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
