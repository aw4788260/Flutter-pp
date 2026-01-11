import 'dart:async';
import 'package:flutter/material.dart';
// import 'dart:ui'; // لم نعد بحاجة إليه هنا في main للنسخة المبسطة
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() {
  // استخدام runZonedGuarded لالتقاط الأخطاء العامة
  runZonedGuarded<Future<void>>(() async {
    // 1. التأكد من ربط الفلاتر بالنظام (ضروري جداً)
    WidgetsFlutterBinding.ensureInitialized();

    // ملاحظة هامة:
    // قمنا بإزالة await Firebase.initializeApp() و _enableSecureMode() من هنا
    // لكي لا يتوقف التطبيق (شاشة سوداء) إذا تأخرت هذه العمليات أو فشلت.
    // سيتم استدعاؤها لاحقاً داخل التطبيق (مثلاً في SplashScreen).

    // 2. تشغيل التطبيق فوراً
    runApp(const EduVantageApp());
    
  }, (error, stack) {
    // تسجيل أي خطأ يحدث أثناء الإقلاع في الكونسول (ويمكن إرساله لـ Crashlytics لاحقاً إذا تمت تهيئته)
    debugPrint("ROOT ERROR: $error");
    // حاول التسجيل في Crashlytics إذا كان مهيأً، وإلا تجاهل لتجنب انهيار آخر
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    } catch (_) {}
  });
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
