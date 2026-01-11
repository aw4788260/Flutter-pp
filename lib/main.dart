import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
// import 'package:firebase_core/firebase_core.dart'; // تعليق مؤقت
// import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // تعليق مؤقت
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 🔥 كود كشف الأخطاء (بدون Firebase) 🔥
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.blueGrey.shade900,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.yellowAccent, size: 60),
                const SizedBox(height: 20),
                const Text(
                  "THE REAL ERROR IS:",
                  style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 20),
                // عرض نص الخطأ الحقيقي
                Text(
                  details.exception.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  "Stack: ${details.stack.toString().split('\n').first}", // السطر الأول فقط من المسار
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
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
    debugPrint("Global Error: $error");
  });
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
