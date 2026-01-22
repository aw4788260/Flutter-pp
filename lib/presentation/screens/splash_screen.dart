import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/security_manager.dart'; // تأكد من المسار الصحيح
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

    // 2. بدء عملية التهيئة
    _initializeApp();
  }

  /// ✅ دالة لحذف الملفات المؤقتة (تنظيف المخلفات)
  Future<void> _cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = dir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            // حذف ملفات PDF المفكوكة وملفات التحميل المؤقتة
            final filename = entity.uri.pathSegments.last;
            if (filename.startsWith('view_') || 
                filename.startsWith('temp_') || 
                filename.startsWith('downloading_')) {
              try { 
                await entity.delete(); 
                debugPrint("🧹 Deleted temp file: $filename");
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Cleanup error: $e");
    }
  }

  // نافذة الموافقة على الشروط والسياسات
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
          content: SingleChildScrollView(
            child: Column(
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
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
              child: const Text("DECLINE", style: TextStyle(color: AppColors.error)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text("ACCEPT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  Future<void> _initializeApp() async {
    try {
      // ✅ 1. تنظيف الملفات المؤقتة فوراً عند الفتح
      await _cleanupTempFiles();

      // ✅ 2. الفحص الأمني
      bool isSafe = await SecurityManager.instance.checkSecurity();
      if (!isSafe || SecurityManager.instance.isBlocked) {
         return; 
      }

      await Hive.initFlutter();
      var box = await StorageService.openBox('auth_box');
      await StorageService.openBox('downloads_box');
      
      if (SecurityManager.instance.isBlocked) return;

      bool termsAccepted = box.get('terms_accepted', defaultValue: false);
      if (!termsAccepted) {
        await Future.delayed(const Duration(seconds: 1)); 
        if (mounted) {
          if (SecurityManager.instance.isBlocked) return;

          bool userAgreed = await _showTermsDialog(box);
          if (!userAgreed) {
            if (Platform.isAndroid) SystemNavigator.pop();
            exit(0);
          } else {
            await box.put('terms_accepted', true);
          }
        }
      }

      if (SecurityManager.instance.isBlocked) return;

      bool isGuest = box.get('is_guest', defaultValue: false);
      String? userId = box.get('user_id');
      String? deviceId = box.get('device_id');

      await Future.delayed(const Duration(seconds: 1)); 

      if (SecurityManager.instance.isBlocked) return;

      if (isGuest) {
        deviceId ??= 'guest_device_${DateTime.now().millisecondsSinceEpoch}';
        await _initAsGuest(deviceId);
        return;
      }

      if (userId == null || deviceId == null) {
        if (mounted && !SecurityManager.instance.isBlocked) {
           Navigator.of(context).pushReplacement(
             MaterialPageRoute(builder: (_) => const LoginScreen()),
           );
        }
        return;
      }

      await _initAsUser(userId, deviceId, box);

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      if (mounted && !SecurityManager.instance.isBlocked) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

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

      if (response.statusCode == 200) {
        AppState().updateFromInitData(response.data);
      }
    } catch (_) {
    } finally {
      AppState().isGuest = true;
      if (mounted && !SecurityManager.instance.isBlocked) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainWrapper()),
        );
      }
    }
  }

  Future<void> _initAsUser(String userId, String deviceId, Box box) async {
    try {
      // ✅ جلب التوكن لإرساله
      String? token = box.get('jwt_token');

      final response = await _dio.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        await box.put('cached_init_data', response.data);
        AppState().updateFromInitData(response.data);

        // ✅ حفظ/تحديث نوع المستخدم (معلم/طالب) إذا كان موجوداً في الرد
        if (response.data['user'] != null && response.data['user']['role'] != null) {
           await box.put('role', response.data['user']['role']);
        }

        bool isLoggedIn = response.data['isLoggedIn'] ?? false;

        // إذا قال السيرفر أن المستخدم غير مسجل (مثلاً التوكن منتهي أو محظور)
        if (!isLoggedIn) {
          await box.clear(); // حذف البيانات القديمة
          await box.put('terms_accepted', true); 
          
          if (mounted && !SecurityManager.instance.isBlocked) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
          return;
        }

        if (mounted && !SecurityManager.instance.isBlocked) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainWrapper()),
          );
        }
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }

    } catch (serverError) {
      FirebaseCrashlytics.instance.log("Splash Offline Mode: $serverError");
      final cachedData = box.get('cached_init_data');
      
      if (cachedData != null) {
         try {
           AppState().updateFromInitData(Map<String, dynamic>.from(cachedData));
         } catch (_) {}

         if (mounted && !SecurityManager.instance.isBlocked) {
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
         if (mounted && !SecurityManager.instance.isBlocked) {
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
    // حسابات الأبعاد لجعل التصميم متجاوب
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final isTablet = size.shortestSide > 600;

    final logoWidth = size.width * (isLandscape ? 0.25 : (isTablet ? 0.4 : 0.6));

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),

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
                  width: logoWidth,
                  fit: BoxFit.contain,
                ),
              ),
              
              const SizedBox(height: 20),

              const Text(
                "EMPOWERING YOUR GROWTH",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentOrange,
                  letterSpacing: 4.0,
                ),
              ),

              const Spacer(flex: 2),

              Column(
                mainAxisSize: MainAxisSize.min,
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

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
