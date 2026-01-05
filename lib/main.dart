import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
// import 'firebase_options.dart'; // ❌ لم نعد بحاجة لهذا الملف لأنه يحتوي بيانات وهمية
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // تفعيل الحماية
    await _enableSecureMode();

    // ✅ التعديل هنا:
    // نتحقق أولاً إذا كان التطبيق مهيأً مسبقاً (لتجنب Duplicate App)
    if (Firebase.apps.isEmpty) {
      // نستدعي الدالة بدون "options".
      // هذا سيجبر فلاتر على قراءة البيانات الحقيقية من ملف google-services.json
      // بدلاً من قراءة البيانات الوهمية من ملف Dart.
      await Firebase.initializeApp();
    }

    // تسجيل أخطاء فلاتر في Crashlytics
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
      title: 'EduVantage',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
