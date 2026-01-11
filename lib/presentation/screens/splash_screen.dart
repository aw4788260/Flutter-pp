import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; 
import 'login_screen.dart';
import 'main_wrapper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  final Dio _dio = Dio();
  final String _baseUrl = 'https://courses.aw478260.dpdns.org'; 
  
  String _loadingText = "SYSTEM STARTING...";

  @override
  void initState() {
    super.initState();

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _bounceAnimation = Tween<double>(begin: 0.0, end: 15.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    _progressController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // نستخدم StringBuffer لتجميع النص الخام بسرعة وكفاءة
    StringBuffer rawErrorLog = StringBuffer();
    rawErrorLog.writeln("=== STARTING INIT LOG ===");

    try {
      WidgetsFlutterBinding.ensureInitialized();

      // -----------------------------------------------------------
      // 1. Hive Setup
      // -----------------------------------------------------------
      if (mounted) setState(() => _loadingText = "LOADING DATABASE...");
      try {
        await Hive.initFlutter();
        await Hive.openBox('auth_box');
        await Hive.openBox('downloads_box');
        await Hive.openBox('app_cache');
        rawErrorLog.writeln("[✓] Hive Initialized");
      } catch (e, stack) {
        rawErrorLog.writeln("\n[!] HIVE ERROR:");
        rawErrorLog.writeln("Err: $e");
        rawErrorLog.writeln("Stack: $stack\n----------------");
      }

      // -----------------------------------------------------------
      // 2. Firebase Setup (التركيز هنا)
      // -----------------------------------------------------------
      if (mounted) setState(() => _loadingText = "CONNECTING SERVICES...");
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
          rawErrorLog.writeln("[✓] Firebase.initializeApp Success");
        } else {
          rawErrorLog.writeln("[i] Firebase was already initialized");
        }
        
        // محاولة اختبار Crashlytics
        FirebaseCrashlytics.instance.log("Splash Screen Loaded");
        rawErrorLog.writeln("[✓] Crashlytics Connected");
        
      } catch (e, stack) {
        // 🔥🔥🔥 هنا سيتم طباعة اللوج الخام لخطأ الفايربيز 🔥🔥🔥
        rawErrorLog.writeln("\n[!!!!!!] FIREBASE FATAL ERROR [!!!!!!]");
        rawErrorLog.writeln("Error Object: $e");
        rawErrorLog.writeln("Runtime Type: ${e.runtimeType}");
        rawErrorLog.writeln("StackTrace:\n$stack");
        rawErrorLog.writeln("--------------------------------------\n");
      }

      // -----------------------------------------------------------
      // 3. Secure Mode
      // -----------------------------------------------------------
      try {
        await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
        rawErrorLog.writeln("[✓] Secure Mode Enabled");
      } catch (e, stack) {
        rawErrorLog.writeln("\n[!] SECURE MODE ERROR:");
        rawErrorLog.writeln("Err: $e");
        // rawErrorLog.writeln("Stack: $stack"); // اختياري لتقليل الزحمة
      }

      // -----------------------------------------------------------
      // 4. Server Connection
      // -----------------------------------------------------------
      if (mounted) setState(() => _loadingText = "CONNECTING TO SERVER...");
      
      String? userId;
      String? deviceId;
      try {
        var authBox = Hive.box('auth_box');
        userId = authBox.get('user_id');
        deviceId = authBox.get('device_id');
      } catch (_) {}

      final response = await _dio.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        rawErrorLog.writeln("[✓] Server Connected (200 OK)");
        
        try {
           var cacheBox = Hive.box('app_cache');
           await cacheBox.put('init_data', response.data);
        } catch (_) {} 
        
        AppState().updateFromInitData(response.data);

        bool isLoggedIn = response.data['isLoggedIn'] ?? false;
        if (mounted) _navigateToNextScreen(isLoggedIn);
        
      } else {
        throw Exception("Server Error Code: ${response.statusCode}");
      }

    } catch (e, stack) {
      // 🛑 الخطأ الرئيسي الذي يوقف التطبيق
      rawErrorLog.writeln("\n[!!!!!!] MAIN CRASH [!!!!!!]");
      rawErrorLog.writeln("Error: $e");
      rawErrorLog.writeln("Stack: $stack");
      
      debugPrint("Full Error Log:\n$rawErrorLog");

      if (mounted) {
        setState(() => _loadingText = "FAILED.");
        // تمرير اللوج الكامل للدالة
        await _tryLoadOfflineData(fullRawLog: rawErrorLog.toString());
      }
    }
  }

  Future<void> _tryLoadOfflineData({required String fullRawLog}) async {
    StringBuffer updatedLog = StringBuffer(fullRawLog);
    
    try {
      if (!Hive.isBoxOpen('app_cache')) {
         try {
           await Hive.initFlutter();
           await Hive.openBox('app_cache');
         } catch (e) {
            updatedLog.writeln("\n[!] Offline Storage Failed: $e");
            if (mounted) _showErrorDialog(updatedLog.toString());
            return;
         }
      }
      
      var cacheBox = Hive.box('app_cache');
      var cachedData = cacheBox.get('init_data');

      if (cachedData != null) {
        AppState().updateFromInitData(cachedData);
        if (mounted) {
           // حتى لو نجحنا في الدخول أوفلاين، سنعرض اللوج إذا كان هناك خطأ في الفايربيز
           // يمكنك إزالة هذا الشرط لاحقاً إذا أردت الدخول بصمت
           if (fullRawLog.contains("FIREBASE FATAL ERROR")) {
             _showErrorDialog(updatedLog.toString(), isWarning: true);
           } else {
             _navigateToNextScreen(true);
           }
        }
      } else {
        updatedLog.writeln("\n[X] No Offline Data Found.");
        if (mounted) _showErrorDialog(updatedLog.toString());
      }
    } catch (e, stack) {
      updatedLog.writeln("\n[!] Critical Offline Error: $e");
      updatedLog.writeln("Stack: $stack");
      if (mounted) _showErrorDialog(updatedLog.toString());
    }
  }

  void _navigateToNextScreen(bool isLoggedIn) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => isLoggedIn ? const MainWrapper() : const LoginScreen(),
      ),
    );
  }

  void _showErrorDialog(String logContent, {bool isWarning = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(
          isWarning ? "Warning (Logs)" : "Critical Error", 
          style: TextStyle(color: isWarning ? Colors.orange : Colors.red),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isWarning 
                  ? "App loaded offline, but errors occurred:" 
                  : "Please share this screen with the developer:",
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              
              // 🖥️ منطقة عرض اللوج (تشبه التيرمينال)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.grey.withOpacity(0.5)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText( // جعل النص قابلاً للنسخ
                      logContent,
                      style: const TextStyle(
                        color: Colors.greenAccent, // لون الهاكرز :)
                        fontFamily: 'monospace', 
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
               // نسخ اللوج للحافظة (اختياري، يتطلب Clipboard)
               // Clipboard.setData(ClipboardData(text: logContent));
            },
            child: const Text("COPY", style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isWarning) {
                 _navigateToNextScreen(true); // إكمال الدخول رغم التحذير
              } else {
                 setState(() => _loadingText = "RETRYING...");
                 _initializeApp();
              }
            },
            child: Text(
              isWarning ? "CONTINUE" : "RETRY", 
              style: const TextStyle(color: AppColors.accentYellow),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _bounceAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, -_bounceAnimation.value),
                      child: child,
                    );
                  },
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: screenWidth * 0.6,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "EMPOWERING YOUR GROWTH",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentOrange,
                    letterSpacing: 4.0,
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 80,
              child: Column(
                children: [
                  Container(
                    width: 160,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.4 + (0.6 * _progressAnimation.value),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accentYellow.withOpacity(0.6),
                                  blurRadius: 12,
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _loadingText, 
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6.0,
                      color: AppColors.textSecondary.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
