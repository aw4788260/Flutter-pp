import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
  String _loadingText = "LOADING SYSTEM";

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("App Started - Splash Screen");

    // 1. إعدادات الأنيميشن
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

    // 2. بدء عملية التهيئة
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // فتح صناديق التخزين الأساسية
      await Hive.initFlutter();
      var authBox = await Hive.openBox('auth_box');
      await Hive.openBox('downloads_box');
      var cacheBox = await Hive.openBox('app_cache'); // صندوق الكاش للبيانات
      
      String? userId = authBox.get('user_id');
      String? deviceId = authBox.get('device_id');

      // لضمان ظهور شعار التطبيق لفترة كافية
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _loadingText = "CONNECTING...");

      // محاولة الاتصال بالسيرفر لجلب أحدث البيانات
      final response = await _dio.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
          // تحديد مهلة اتصال قصيرة (6 ثواني) لضمان عدم تعليق المستخدم
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        // ✅ نجاح الاتصال: تحديث الكاش بالبيانات الجديدة للاستخدام أوفلاين لاحقاً
        await cacheBox.put('init_data', response.data);

        // تحديث حالة التطبيق العامة
        AppState().updateFromInitData(response.data);

        bool isLoggedIn = response.data['isLoggedIn'] ?? false;
        
        // التحقق من صحة الجلسة: إذا انتهت الجلسة في السيرفر، نمسح البيانات المحلية
        if (userId != null && !isLoggedIn) {
          await authBox.clear();
        }

        if (mounted) _navigateToNextScreen(isLoggedIn);
        
      } else {
        throw Exception("Server Error");
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.log("Splash Connection Failed: $e");
      
      // ❌ في حالة الفشل (أوفلاين أو خطأ سيرفر): محاولة تحميل الكاش المحفوظ
      if (mounted) {
        setState(() => _loadingText = "OFFLINE MODE...");
        await _tryLoadOfflineData();
      }
    }
  }

  // ✅ دالة محاولة التحميل من الذاكرة المحلية (الدعم أوفلاين)
  Future<void> _tryLoadOfflineData() async {
    try {
      var cacheBox = await Hive.openBox('app_cache');
      var cachedData = cacheBox.get('init_data');
      var authBox = await Hive.openBox('auth_box');
      String? userId = authBox.get('user_id');

      if (cachedData != null) {
        // ✅ وجدنا بيانات محفوظة سابقاً!
        AppState().updateFromInitData(Map<String, dynamic>.from(cachedData));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No Internet Connection. Using saved offline data."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          
          // إذا كان مسجل دخول سابقاً ولديه userId، نعتبره مسجل دخول في وضع الأوفلاين
          _navigateToNextScreen(userId != null);
        }
      } else {
        // ❌ لا توجد بيانات محفوظة ولا إنترنت
        if (mounted) _showRetryDialog();
      }
    } catch (e) {
      if (mounted) _showRetryDialog();
    }
  }

  void _navigateToNextScreen(bool isLoggedIn) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => isLoggedIn ? const MainWrapper() : const LoginScreen(),
      ),
    );
  }

  void _showRetryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: const Text("Connection Error", style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          "Could not connect to the server and no offline data found.\nPlease check your internet connection.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _loadingText = "RETRYING...");
              _initializeApp(); 
            },
            child: const Text("RETRY", style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold)),
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
              children: [
                // اللوجو المتحرك (Bounce)
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
            
            // شريط التحميل السفلي
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
