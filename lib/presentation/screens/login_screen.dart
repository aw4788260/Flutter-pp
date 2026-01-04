import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/custom_text_field.dart';
import 'register_screen.dart';
import 'main_wrapper.dart'; // ✅ إضافة استيراد الشاشة الرئيسية

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("User visited Login Screen");
  }

  void _handleLogin() {
    // ⚠️ ملاحظة: هنا يجب وضع منطق التحقق من الـ API لاحقاً
    // حالياً سنقوم بتسجيل الدخول المباشر للانتقال للخطوة التالية
    
    FirebaseCrashlytics.instance.log("User logged in successfully");

    // ✅ الانتقال للشاشة الرئيسية (MainWrapper)
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainWrapper()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary, 
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            children: [
              const Spacer(flex: 1), 

              // --- Header ---
              Container(
                width: 64, height: 64, 
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(16), 
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.shield, color: AppColors.accentYellow, size: 32),
              ),
              const SizedBox(height: 24),

              const Text(
                "LOGIN",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5, 
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "PLEASE LOGIN TO CONTINUE.",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentYellow,
                  letterSpacing: 2.0, 
                ),
              ),

              const SizedBox(height: 48), 

              // --- Form ---
              CustomTextField(
                label: "Username or Phone",
                hint: "e.g. @john or 01012345678",
                icon: LucideIcons.user,
                controller: _identifierController,
              ),
              const SizedBox(height: 24), 

              CustomTextField(
                label: "Password",
                hint: "••••••••",
                icon: LucideIcons.lock,
                isPassword: true,
                controller: _passwordController,
              ),
              const SizedBox(height: 32),

              // --- Sign In Button ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleLogin, // ✅ تم ربط الدالة
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20), 
                    ),
                    elevation: 10,
                    shadowColor: AppColors.accentYellow.withOpacity(0.2), 
                  ),
                  child: Row(
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
              ),

              const Spacer(flex: 2),

              // --- Register Link ---
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
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
