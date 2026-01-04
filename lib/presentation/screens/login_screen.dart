import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart'; // تأكد من إضافة المكتبة
import '../../core/constants/app_colors.dart';
import '../widgets/custom_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  void _handleLogin() {
    // سيتم إضافة المنطق في المرحلة الثالثة
    print("Login: ${_usernameController.text}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary, // bg-background-primary
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0), // p-8
          child: Column(
            children: [
              const Spacer(flex: 1), // mb-12 mt-16 roughly

              // --- Header Icon ---
              Container(
                width: 64, height: 64, // w-16 h-16
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(16), // rounded-2xl
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

              // --- Title ---
              const Text(
                "LOGIN",
                style: TextStyle(
                  fontSize: 30, // text-3xl
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5, // tracking-tight
                ),
              ),
              const SizedBox(height: 8),

              // --- Subtitle ---
              const Text(
                "PLEASE LOGIN TO CONTINUE.",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentYellow,
                  letterSpacing: 2.0, // tracking-widest
                ),
              ),

              const SizedBox(height: 48), // Space between header and form

              // --- Form ---
              CustomTextField(
                label: "Username or Phone",
                hint: "e.g. @john or 01012345678",
                icon: LucideIcons.user,
                controller: _usernameController,
              ),
              const SizedBox(height: 24), // space-y-6

              CustomTextField(
                label: "Password",
                hint: "••••••••",
                icon: LucideIcons.lock,
                isPassword: true,
                controller: _passwordController,
              ),
              const SizedBox(height: 32),

              // --- Submit Button ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary, // Text color
                    padding: const EdgeInsets.symmetric(vertical: 20), // py-5
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20), // rounded-m3-xl (approx 20-28)
                    ),
                    elevation: 10,
                    shadowColor: AppColors.accentYellow.withOpacity(0.2), // shadow-lg
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
                      SizedBox(width: 12), // gap-3
                      Icon(LucideIcons.arrowRight, size: 18),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 2), // mt-auto

              // --- Footer ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "New student? ",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Navigate to Register
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
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
