import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; // ✅ استيراد مصدر البيانات الحقيقي
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'my_requests_screen.dart';
import 'dev_info_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  
  // دالة تسجيل الخروج (أو العودة لصفحة الدخول للضيف)
  Future<void> _logout() async {
    try {
      // 1. مسح البيانات من التخزين المحلي (بما في ذلك is_guest)
      var authBox = await Hive.openBox('auth_box');
      await authBox.clear();
      
      // 2. مسح البيانات من الذاكرة
      AppState().clear();

      if (mounted) {
        // 3. التوجيه لشاشة تسجيل الدخول ومسح كل الصفحات السابقة
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("Logout Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 1. التحقق من حالة الضيف وجلب البيانات
    final isGuest = AppState().isGuest;
    final user = AppState().userData;

    // ✅ 2. ضبط النصوص بناءً على الحالة
    final String name = isGuest ? "GUEST USER" : (user?['first_name'] ?? "User").toUpperCase();
    final String username = isGuest ? "Not Logged In" : (user?['username'] ?? "@user");
    final String firstLetter = isGuest ? "?" : (name.isNotEmpty ? name[0] : "U");

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "MY PROFILE",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "MANAGE YOUR ACCOUNT",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentYellow,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 32),

              // --- User Info Card ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                ),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accentYellow.withOpacity(0.5), width: 2),
                      ),
                      child: Center(
                        child: Text(
                          firstLetter,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentYellow,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundPrimary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              username,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // ✅ إخفاء زر التعديل إذا كان المستخدم ضيفاً
                    if (!isGuest)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())).then((_) => setState(() {}));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: const Icon(LucideIcons.edit2, size: 16, color: AppColors.accentYellow),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // --- Account Settings (Only for Registered Users) ---
              // ✅ إخفاء القسم بالكامل للضيوف
              if (!isGuest) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    "ACCOUNT SETTINGS",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildMenuItem(context, icon: LucideIcons.user, title: "Edit Profile", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())).then((_) => setState(() {}))),
                      const Divider(height: 1, color: Colors.white10),
                      _buildMenuItem(context, icon: LucideIcons.lock, title: "Change Password", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
                      const Divider(height: 1, color: Colors.white10),
                      _buildMenuItem(context, icon: LucideIcons.clipboardList, title: "My Requests", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRequestsScreen()))),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // --- General Settings (For Everyone) ---
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  "GENERAL",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildMenuItem(
                      context, 
                      icon: LucideIcons.info, 
                      title: "App Information", 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevInfoScreen()))
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // --- Action Button (Logout / Login) ---
              GestureDetector(
                onTap: _logout, // نفس الدالة تقوم بالتنظيف والتوجيه لصفحة الدخول
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    // ✅ تغيير اللون إذا كان ضيفاً (أصفر للدخول، أحمر للخروج)
                    color: isGuest ? AppColors.accentYellow : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isGuest ? AppColors.accentYellow : AppColors.error.withOpacity(0.2)
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isGuest ? LucideIcons.logIn : LucideIcons.logOut, 
                        color: isGuest ? AppColors.backgroundPrimary : AppColors.error, 
                        size: 18
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isGuest ? "LOGIN / REGISTER" : "LOGOUT", // ✅ تغيير النص
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.bold, 
                          color: isGuest ? AppColors.backgroundPrimary : AppColors.error, 
                          letterSpacing: 1.5
                        )
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap, String? badge}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                ),
                child: Icon(icon, size: 18, color: AppColors.accentYellow),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.accentOrange, borderRadius: BorderRadius.circular(50)),
                  child: Text(badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
