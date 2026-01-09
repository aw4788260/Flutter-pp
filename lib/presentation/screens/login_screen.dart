import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import 'main_wrapper.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final Dio _dio = Dio();
  final String _baseUrl = 'https://courses.aw478260.dpdns.org'; // رابط السيرفر

  bool _isLoading = false;
  String? _errorMessage;

  // لتوليد بصمة جهاز فريدة إذا لم تكن موجودة
  String _getOrCreateDeviceId(Box box) {
    String? deviceId = box.get('device_id');
    if (deviceId == null) {
      // توليد معرف عشوائي كبصمة للجهاز
      final random = Random();
      final date = DateTime.now().millisecondsSinceEpoch;
      final rand = random.nextInt(1000000);
      deviceId = 'app_v1_${date}_$rand';
      box.put('device_id', deviceId);
    }
    return deviceId;
  }

  Future<void> _handleLogin() async {
    final username = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "يرجى إدخال اسم المستخدم وكلمة المرور");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var box = await Hive.openBox('auth_box');
      final deviceId = _getOrCreateDeviceId(box);

      // 1. طلب تسجيل الدخول
      final response = await _dio.post(
        '$_baseUrl/api/auth/login',
        data: {
          'username': username,
          'password': password,
          'deviceId': deviceId,
        },
        options: Options(
          validateStatus: (status) => status! < 500, // لمعالجة أخطاء 401/403 يدوياً
        ),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['success'] == true) {
        // 2. حفظ البيانات محلياً
        final userMap = data['user'];
        await box.put('user_id', userMap['id'].toString());
        await box.put('username', userMap['username']);
        await box.put('first_name', userMap['firstName']);
        
        // 3. جلب بيانات التهيئة (الكورسات والاشتراكات) قبل الدخول
        await _fetchInitData(userMap['id'].toString(), deviceId);

        // 4. الانتقال للرئيسية
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainWrapper()),
          );
        }
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'فشل تسجيل الدخول';
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _errorMessage = "حدث خطأ في الاتصال بالسيرفر");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // دالة مساعدة لجلب البيانات الأولية وتحديث State التطبيق
  Future<void> _fetchInitData(String userId, String deviceId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(headers: {
          'x-user-id': userId,
          'x-device-id': deviceId,
        }),
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        AppState().updateFromInitData(response.data);
      }
    } catch (e) {
      // حتى لو فشل جلب البيانات، سنسمح بالدخول وسيحاول التطبيق جلبها لاحقاً
      debugPrint("Init Data Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 64),
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  "LOGIN",
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  "PLEASE LOGIN TO CONTINUE.",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentYellow,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // عرض رسالة الخطأ إن وجدت
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              _buildTextField(
                controller: _identifierController,
                hint: "Username",
                icon: LucideIcons.user,
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _passwordController,
                hint: "Password",
                icon: LucideIcons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: AppColors.backgroundPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 10,
                  shadowColor: AppColors.accentYellow.withOpacity(0.2),
                ),
                child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.backgroundPrimary))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          "SIGN IN",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.0,
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(LucideIcons.arrowRight, size: 18),
                      ],
                    ),
              ),

              const SizedBox(height: 48),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "New student? ",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: const Text(
                      "CREATE ACCOUNT",
                      style: TextStyle(
                        color: AppColors.accentYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.accentYellow,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        cursorColor: AppColors.accentYellow,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          prefixIcon: Icon(
            icon,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
