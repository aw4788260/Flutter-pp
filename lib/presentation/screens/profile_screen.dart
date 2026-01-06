import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'my_requests_screen.dart';
import 'dev_info_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
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

              // User Info Card
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
                    // ✅ Avatar: Logo Image
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accentYellow.withOpacity(0.5), width: 2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0), // مسافة داخلية ليكون اللوجو واضحاً
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Texts
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "AHMED WALID",
                            style: TextStyle(
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
                            child: const Text(
                              "@aw478260",
                              style: TextStyle(
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
                    // Edit Icon
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
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

              // Account Settings
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  "ACCOUNT SETTINGS",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 2.0,
                  ),
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
                    _buildMenuItem(context, icon: LucideIcons.user, title: "Edit Profile", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()))),
                    const Divider(height: 1, color: Colors.white10),
                    _buildMenuItem(context, icon: LucideIcons.lock, title: "Change Password", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
                    const Divider(height: 1, color: Colors.white10),
                    _buildMenuItem(context, icon: LucideIcons.clipboardList, title: "My Requests", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRequestsScreen())), badge: "3"),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // General
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  "GENERAL",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 2.0,
                  ),
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
                    _buildMenuItem(context, icon: LucideIcons.info, title: "App Information", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevInfoScreen()))),
                    // ❌ تم حذف خيار المشاركة
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Logout
              GestureDetector(
                onTap: () {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.error.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(LucideIcons.logOut, color: AppColors.error, size: 18),
                      SizedBox(width: 12),
                      Text("LOGOUT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.error, letterSpacing: 1.5)),
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
