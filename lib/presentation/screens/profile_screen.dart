import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';

// شاشات الإعدادات العامة
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'dev_info_screen.dart';
import 'login_screen.dart';

// شاشات الطالب
import 'my_requests_screen.dart';

// شاشات المعلم
import 'teacher/student_requests_screen.dart';
import 'teacher/manage_students_screen.dart';
import 'teacher/manage_team_screen.dart';
import 'teacher/financial_stats_screen.dart'; // ✅ تم إضافة استيراد شاشة الإحصائيات

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';
  bool _isTeacher = false; // لتخزين حالة المعلم

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  // ✅ التحقق من الصلاحية (هل هو معلم؟)
  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
      });
    }
  }

  // دالة تسجيل الخروج
  Future<void> _logout() async {
    try {
      var authBox = await StorageService.openBox('auth_box');
      final token = authBox.get('jwt_token');
      final deviceId = authBox.get('device_id');

      // 1. إرسال طلب للسيرفر لحذف التوكن
      if (token != null && deviceId != null) {
        try {
          await Dio().post(
            '$_baseUrl/api/auth/logout',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'x-device-id': deviceId,
                'x-app-secret': const String.fromEnvironment('APP_SECRET'),
              },
              validateStatus: (status) => status! < 500,
              sendTimeout: const Duration(seconds: 3),
            ),
          );
        } catch (e) {
          debugPrint("Server Logout Warning: $e");
        }
      }

      // 2. مسح البيانات محلياً
      await authBox.clear();
      
      // 3. مسح الذاكرة
      AppState().clear();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("Local Logout Error: $e");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = AppState().isGuest;
    final user = AppState().userData;

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
              Text(
                _isTeacher ? "TEACHER DASHBOARD" : "MANAGE YOUR ACCOUNT",
                style: const TextStyle(
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

              // ========================================================
              // 🟢 قسم المعلم (يظهر فقط للمعلم)
              // ========================================================
              if (_isTeacher && !isGuest) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    "TEACHER CONTROLS",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // 1. طلبات الاشتراك
                      _buildMenuItem(
                        context, 
                        icon: LucideIcons.bellRing, 
                        title: "Incoming Requests", 
                        // badge: "NEW", // ❌ تم حذف الشارة كما طلبت
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentRequestsScreen()))
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      
                      // 2. إدارة الطلاب
                      _buildMenuItem(
                        context, 
                        icon: LucideIcons.users, 
                        title: "My Students", 
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageStudentsScreen()))
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      
                      // 3. فريق العمل
                      _buildMenuItem(
                        context, 
                        icon: LucideIcons.shieldCheck, 
                        title: "Manage Team", 
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageTeamScreen()))
                      ),
                      const Divider(height: 1, color: Colors.white10),

                      // 4. ✅ زر الإحصائيات المالية (جديد)
                      _buildMenuItem(
                        context, 
                        icon: LucideIcons.barChart2, 
                        title: "Financial Stats", 
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialStatsScreen()))
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // --- Account Settings (للجميع ما عدا الضيف) ---
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
                      
                      // ⚠️ إظهار "طلباتي" فقط للطالب (لأن المعلم لديه لوحة تحكم أعلاه)
                      if (!_isTeacher) ...[
                        const Divider(height: 1, color: Colors.white10),
                        _buildMenuItem(context, icon: LucideIcons.clipboardList, title: "My Requests", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRequestsScreen()))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // --- General Settings ---
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

              // --- Logout Button ---
              GestureDetector(
                onTap: _logout, 
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
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
                        isGuest ? "LOGIN / REGISTER" : "LOGOUT", 
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
