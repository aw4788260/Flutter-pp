import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'home_screen.dart';
import 'my_courses_screen.dart';
import 'profile_screen.dart';
import 'downloaded_files_screen.dart'; // ✅ استيراد صفحة التحميلات

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  // القوائم المرتبطة بالأزرار
  final List<Widget> _pages = [
    const HomeScreen(),
    const MyCoursesScreen(),
    const DownloadedFilesScreen(), // ✅ الصفحة الحقيقية للتحميلات
    const ProfileScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      // ✅ Custom Bottom Navigation (تصميم مخصص يطابق التصميم الأصلي)
      bottomNavigationBar: Container(
        height: 80, // ارتفاع الشريط
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withOpacity(0.9), // لون خلفية نصف شفاف
          border: const Border(
            top: BorderSide(color: Colors.white10), // خط فاصل علوي خفيف
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, LucideIcons.home, "Home"),
            _buildNavItem(1, LucideIcons.bookOpen, "Courses"),
            _buildNavItem(2, LucideIcons.download, "Downloads"), // أيقونة التحميلات
            _buildNavItem(3, LucideIcons.user, "Profile"),
          ],
        ),
      ),
    );
  }

  // ودجت بناء العنصر المخصص في الشريط السفلي
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80, // عرض منطقة اللمس
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. المؤشر العلوي المضيء (يظهر فقط عند التحديد)
            if (isSelected)
              Positioned(
                top: 0,
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentYellow.withOpacity(0.5),
                        blurRadius: 12, // تأثير التوهج (Glow)
                      )
                    ],
                  ),
                ),
              ),

            // 2. الأيقونة والنص
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8), 
                Icon(
                  icon,
                  size: 24,
                  color: isSelected ? AppColors.accentYellow : AppColors.textSecondary,
                ),
                const SizedBox(height: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5, // تباعد الأحرف المميز للتصميم
                    color: isSelected 
                        ? AppColors.accentYellow 
                        : AppColors.textSecondary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
