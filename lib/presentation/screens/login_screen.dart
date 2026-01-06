import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
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

  // Focus Nodes for styling changes
  final FocusNode _userFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Entered Login Screen");
    // Rebuild on focus change to update icon colors
    _userFocus.addListener(() => setState(() {}));
    _passFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _handleLogin() {
    // محاكاة تسجيل الدخول
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 64), // mt-16 approx

              // --- Header Section ---
              Center(
                child: Container(
                  width: 64, height: 64, // w-16 h-16
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(LucideIcons.shield, color: AppColors.accentYellow, size: 32),
                ),
              ),
              const Center(
                child: Text(
                  "LOGIN",
                  style: TextStyle(
                    fontSize: 30, // text-3xl
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

              // --- Form Section ---
              
              // 1. Username Input
              _buildInputLabel("Username or Phone"),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _identifierController,
                focusNode: _userFocus,
                hint: "e.g. @john or 01012345678",
                icon: LucideIcons.user,
              ),
              const SizedBox(height: 24),

              // 2. Password Input
              _buildInputLabel("Password"),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _passwordController,
                focusNode: _passFocus,
                hint: "••••••••",
                icon: LucideIcons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 32),

              // --- Sign In Button ---
              ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: AppColors.backgroundPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24), // rounded-m3-xl (custom larger radius)
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

              const SizedBox(height: 48),

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

  // Helper for Label Styles
  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.accentYellow,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  // Helper for TextField Styles matching React
  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    final isActive = controller.text.isNotEmpty || focusNode.hasFocus;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16), // rounded-m3-lg
        border: Border.all(
          color: focusNode.hasFocus 
              ? AppColors.accentYellow.withOpacity(0.5) 
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isPassword,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        cursorColor: AppColors.accentYellow,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          prefixIcon: Icon(
            icon,
            size: 18,
            color: isActive ? AppColors.accentYellow : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
