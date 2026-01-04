import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // مهم لاستدعاء القنوات
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. تفعيل حماية تصوير الشاشة (Android Only)
    // هذا الكود يستدعي كود Native لمنع التصوير
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

// دالة تفعيل الحماية
Future<void> _enableSecureMode() async {
  try {
    // سنستخدم مكتبة flutter_windowmanager إذا كانت مثبتة، 
    // أو يمكننا الاعتماد على القنوات (MethodChannel) إذا كنت تفضل الكود الـ Native
    // للأمان القصوى سنفترض وجود flutter_windowmanager في pubspec.yaml
    const platform = MethodChannel('flutter_windowmanager');
    await platform.invokeMethod('addFlags', {'flags': 8192}); // FLAG_SECURE = 8192
  } catch (e) {
    print("Failed to enable secure mode: $e");
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
