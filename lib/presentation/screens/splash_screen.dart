import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; // تأكد من وجود هذا الملف
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
  // ⚠️ استبدل هذا الرابط برابط الباك اند الحقيقي الخاص بك
  final String _baseUrl = 'https://courses.aw478260.dpdns.org'; 

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("App Started - Splash Screen");

    // 1. إعدادات الأنيميشن (نفس التصميم الأصلي)
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

    // 2. بدء عملية التهيئة والاتصال
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // فتح صندوق التخزين المحلي
      await Hive.initFlutter();
      var box = await Hive.openBox('auth_box');
      await Hive.openBox('downloads_box'); // لفتح صندوق التحميلات مبكراً
      
      String? userId = box.get('user_id');
      String? deviceId = box.get('device_id');

      // محاكاة وقت التحميل (لإكمال الأنيميشن)
      await Future.delayed(const Duration(seconds: 2));

      // استدعاء API التهيئة
      final response = await _dio.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
          },
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        // تحديث البيانات في الذاكرة
        AppState().updateFromInitData(response.data);

        bool isLoggedIn = response.data['isLoggedIn'] ?? false;

        // إذا فشل التحقق من السيرفر، نعتبره خروج
        if (userId != null && !isLoggedIn) {
          await box.clear();
        }

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => isLoggedIn ? const MainWrapper() : const LoginScreen(),
            ),
          );
        }
      } else {
        throw Exception("Failed to init data");
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      // في حالة الخطأ، نذهب لتسجيل الدخول كاحتياط
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
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
                // اللوجو المتحرك
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
                  // شريط التقدم المخصص
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
                    "LOADING SYSTEM",
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
