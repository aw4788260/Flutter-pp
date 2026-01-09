import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; // للاتصال بالشبكة
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Focus Nodes
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  final _confirmPassFocus = FocusNode();

  final Dio _dio = Dio();
  final String _baseUrl = 'https://courses.aw478260.dpdns.org'; // رابط السيرفر

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Entered Register Screen");
    // Rebuild on focus change for styling
    for (var node in [_nameFocus, _phoneFocus, _userFocus, _passFocus, _confirmPassFocus]) {
      node.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _confirmPassFocus.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    // 1. تصفير الأخطاء
    setState(() => _errorMessage = null);

    // 2. التحقق من المدخلات (Validation)
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty || phone.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "جميع الحقول مطلوبة");
      return;
    }

    // التحقق من اسم المستخدم (إنجليزي وأرقام فقط)
    final usernameRegex = RegExp(r'^[a-zA-Z0-9]+$');
    if (!usernameRegex.hasMatch(username)) {
      setState(() => _errorMessage = "اسم المستخدم يجب أن يحتوي على أحرف إنجليزية وأرقام فقط (بدون مسافات)");
      return;
    }

    // التحقق من رقم الهاتف (يبدأ بـ 01 ويتكون من 11 رقم)
    final phoneRegex = RegExp(r'^01[0-9]{9}$');
    if (!phoneRegex.hasMatch(phone)) {
      setState(() => _errorMessage = "رقم الهاتف غير صحيح (يجب أن يكون 11 رقم ويبدأ بـ 01)");
      return;
    }

    // التحقق من كلمة المرور
    if (password.length < 6) {
      setState(() => _errorMessage = "كلمة المرور يجب أن تكون 6 أحرف على الأقل");
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = "كلمات المرور غير متطابقة");
      return;
    }

    // 3. إرسال الطلب
    setState(() => _isLoading = true);

    try {
      final response = await _dio.post(
        '$_baseUrl/api/auth/signup',
        data: {
          'firstName': name,
          'username': username,
          'phone': phone,
          'password': password,
        },
        options: Options(
          validateStatus: (status) => status! < 500,
        ),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['success'] == true) {
        // نجاح
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? "تم إنشاء الحساب بنجاح. قم بتسجيل الدخول."),
              backgroundColor: AppColors.success,
            ),
          );
          // التوجيه لصفحة تسجيل الدخول
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      } else {
        // خطأ من السيرفر (مثل تكرار الاسم)
        setState(() => _errorMessage = data['message'] ?? "فشل إنشاء الحساب");
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _errorMessage = "حدث خطأ في الاتصال بالسيرفر");
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              
              // Back Button
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: IconButton(
                  icon: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              // Header
              const Text(
                "CREATE ACCOUNT",
                style: TextStyle(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "FILL IN THE DETAILS TO JOIN US.",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentYellow,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 32),

              // Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertCircle, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // --- Form Fields ---

              // 1. Full Name
              _buildInputLabel("Full Name"),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _nameController,
                focusNode: _nameFocus,
                hint: "Your full name",
                icon: LucideIcons.user,
              ),
              const SizedBox(height: 16),

              // 2. Phone Number
              _buildInputLabel("Phone Number"),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                hint: "01xxxxxxxxx",
                icon: LucideIcons.phone,
                inputType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // 3. Username
              _buildInputLabel("Username (English Only)"),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _usernameController,
                focusNode: _userFocus,
                hint: "username",
                icon: LucideIcons.atSign,
              ),
              const SizedBox(height: 16),

              // 4. Password
              _buildInputLabel("Password"),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _passwordController,
                focusNode: _passFocus,
                hint: "••••••",
                icon: LucideIcons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 16),

              // 5. Confirm Password
              _buildInputLabel("Confirm Password"),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _confirmPasswordController,
                focusNode: _confirmPassFocus,
                hint: "••••••",
                icon: LucideIcons.lock, 
                isPassword: true,
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
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
                            "CREATE ACCOUNT",
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

              const SizedBox(height: 32),

              // Footer
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Already have an account? ",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    GestureDetector(
                      onTap: () {
                         Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                      },
                      child: const Text(
                        "SIGN IN",
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
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType inputType = TextInputType.text,
  }) {
    final isActive = controller.text.isNotEmpty || focusNode.hasFocus;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
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
        keyboardType: inputType,
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
