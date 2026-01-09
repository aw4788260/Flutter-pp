import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; // استدعاء المخزن الجديد
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
  final Dio _dio = Dio();

  // رابط الباك اند الخاص بك (تأكد من تغييره للرابط الحقيقي)
  final String _baseUrl = 'https://courses.aw478260.dpdns.org'; 

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("App Started - Splash Screen");

    // Animation Setup
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _bounceAnimation = Tween<double>(begin: 0.0, end: 15.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // البدء في عملية التهيئة
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. فتح صندوق التخزين المحلي
      await Hive.initFlutter();
      var box = await Hive.openBox('auth_box');
      
      String? userId = box.get('user_id');
      String? deviceId = box.get('device_id');

      // 2. استدعاء API التهيئة
      // نرسل الهيدرز حتى لو كانت null، الباك اند سيتعامل معها
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
        // 3. تخزين البيانات في الذاكرة (State)
        AppState().updateFromInitData(response.data);

        bool isLoggedIn = response.data['isLoggedIn'] ?? false;

        // إذا فشل التحقق من السيرفر (رغم وجود بيانات محلية)، نعتبره خروج
        if (userId != null && !isLoggedIn) {
          await box.clear(); // مسح البيانات القديمة
        }

        // 4. التوجيه
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
      // تسجيل الخطأ
      FirebaseCrashlytics.instance.recordError(e, stack);
      debugPrint("Splash Error: $e");
      
      // في حالة الخطأ (انترنت مثلاً)، نذهب لتسجيل الدخول كاحتياط
      // أو يمكن إظهار رسالة خطأ وإعادة المحاولة
      if (mounted) {
        // تأخير بسيط لإظهار اللوجو
        Future.delayed(const Duration(seconds: 2), () {
           Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
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
            const Positioned(
              bottom: 80,
              child: CircularProgressIndicator(color: AppColors.accentYellow),
            ),
          ],
        ),
      ),
    );
  }
}
