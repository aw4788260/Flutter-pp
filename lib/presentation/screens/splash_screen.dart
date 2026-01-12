import 'dart:async';
import 'dart:io'; // للخروج من التطبيق
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // لإغلاق التطبيق
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:safe_device/safe_device.dart'; // ✅ مكتبة الحماية
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; 
import 'login_screen.dart';
import 'main_wrapper.dart';
import 'privacy_policy_screen.dart'; 
import 'terms_conditions_screen.dart'; 

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

    // 2. بدء عملية التهيئة والاتصال
    _initializeApp();
  }

  // ✅ دالة الفحص الأمني (روت / خيارات مطور)
  Future<bool> _checkSecurity() async {
    try {
      bool isJailBroken = await SafeDevice.isJailBroken;
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;

      if (isJailBroken || isDevMode) {
        String reason = "";
        if (isJailBroken) reason = "Root/Jailbreak Detected\n(تم اكتشاف كسر حماية)";
        if (isDevMode) reason = "${reason.isNotEmpty ? '$reason\n' : ''}Developer Options Enabled\n(خيارات المطور مفعلة)";

        if (mounted) {
          _showSecurityBlockDialog(reason);
        }
        return false; // جهاز غير آمن
      }
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(e, null, reason: 'Security Check Failed');
    }
    return true; // جهاز آمن
  }

  // ✅ نافذة الحظر الأمني
  void _showSecurityBlockDialog(String reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: const Row(
            children: [
              Icon(LucideIcons.shieldAlert, color: AppColors.error),
              SizedBox(width: 10),
              Text("Security Alert", style: TextStyle(color: AppColors.error, fontSize: 18)),
            ],
          ),
          content: Text(
            "Security Risk Detected:\n\n$reason\n\nPlease disable these settings to use the app.",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (Platform.isAndroid) SystemNavigator.pop();
                exit(0);
              },
              child: const Text("EXIT", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ نافذة الموافقة على الشروط والسياسات (أول مرة فقط)
  Future<bool> _showTermsDialog(Box box) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Welcome / مرحباً بك",
            style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "يرجى الموافقة على الشروط والأحكام وسياسة الخصوصية للمتابعة.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please accept our Terms & Privacy Policy to continue.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              
              // روابط الصفحات
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.fileText, color: AppColors.accentOrange, size: 20),
                title: const Text("Terms & Conditions", style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsConditionsScreen())),
              ),
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.shield, color: AppColors.accentOrange, size: 20),
                title: const Text("Privacy Policy", style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false), // رفض
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
              child: const Text("DECLINE", style: TextStyle(color: AppColors.error)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true), // موافقة
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text("ACCEPT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  Future<void> _initializeApp() async {
    // 🛡️ 1. تنفيذ الفحص الأمني أولاً
    if (!await _checkSecurity()) return;

    try {
      // فتح صندوق التخزين المحلي
      await Hive.initFlutter();
      var box = await Hive.openBox('auth_box');
      await Hive.openBox('downloads_box'); // لفتح صندوق التحميلات مبكراً
      
      // ✅ 2. التحقق من الموافقة على الشروط (أول مرة)
      bool termsAccepted = box.get('terms_accepted', defaultValue: false);
      if (!termsAccepted) {
        await Future.delayed(const Duration(seconds: 1)); 
        if (mounted) {
          bool userAgreed = await _showTermsDialog(box);
          if (!userAgreed) {
            if (Platform.isAndroid) SystemNavigator.pop();
            exit(0);
          } else {
            await box.put('terms_accepted', true);
          }
        }
      }

      // ✅ 3. قراءة البيانات المحلية (ضيف / مستخدم)
      bool isGuest = box.get('is_guest', defaultValue: false);
      String? userId = box.get('user_id');
      String? deviceId = box.get('device_id');

      await Future.delayed(const Duration(seconds: 1)); // محاكاة وقت التحميل

      // --- المسار الأول: المستخدم ضيف ---
      if (isGuest) {
        // إذا كان ضيفاً، نستخدم معرف جهاز وهمي للطلب إن لم يوجد
        deviceId ??= 'guest_device_${DateTime.now().millisecondsSinceEpoch}';
        await _initAsGuest(deviceId);
        return;
      }

      // --- المسار الثاني: مستخدم عادي ---
      if (userId == null || deviceId == null) {
        // لا يوجد تسجيل دخول -> شاشة الدخول
        if (mounted) {
           Navigator.of(context).pushReplacement(
             MaterialPageRoute(builder: (_) => const LoginScreen()),
           );
        }
        return;
      }

      // محاولة تهيئة المستخدم المسجل
      await _initAsUser(userId, deviceId, box);

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  // ✅ دالة مساعدة لتهيئة الضيف
  Future<void> _initAsGuest(String deviceId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          headers: {
            'x-user-id': '0',
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      // حتى لو فشل الاتصال، سنسمح للضيف بالدخول (وضع الأوفلاين للضيوف)
      if (response.statusCode == 200) {
        AppState().updateFromInitData(response.data);
      }
    } catch (_) {
      // تجاهل الأخطاء للضيف
    } finally {
      AppState().isGuest = true;
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainWrapper()),
        );
      }
    }
  }

  // ✅ دالة مساعدة لتهيئة المستخدم المسجل
  Future<void> _initAsUser(String userId, String deviceId, Box box) async {
    try {
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
        await box.put('cached_init_data', response.data);
        AppState().updateFromInitData(response.data);

        bool isLoggedIn = response.data['isLoggedIn'] ?? false;

        if (!isLoggedIn) {
          // التوكن منتهي أو تم الدخول من جهاز آخر
          await box.clear();
          await box.put('terms_accepted', true); // الحفاظ على حالة الشروط
          
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
          return;
        }

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainWrapper()),
          );
        }
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }

    } catch (serverError) {
      // --- Offline Fallback ---
      FirebaseCrashlytics.instance.log("Splash Offline Mode: $serverError");
      final cachedData = box.get('cached_init_data');
      
      if (cachedData != null) {
         try {
           AppState().updateFromInitData(Map<String, dynamic>.from(cachedData));
         } catch (_) {}

         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(
               content: Text("No Internet. Entering Offline Mode."),
               backgroundColor: AppColors.accentOrange,
               duration: Duration(seconds: 3),
             ),
           );
           Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainWrapper()),
           );
         }
      } else {
         // لا كاش ولا نت -> دخول محدود
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("Offline Mode (Limited Access)"), backgroundColor: Colors.grey),
           );
           Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainWrapper()),
           );
         }
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
