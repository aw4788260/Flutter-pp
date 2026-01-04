import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import 'home_screen.dart';
// سنقوم بإنشاء الصفحات الأخرى لاحقاً، سنضع حاويات مؤقتة الآن
import 'my_courses_screen.dart'; // سننشئه لاحقاً
import 'profile_screen.dart';    // سننشئه لاحقاً

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  // قائمة الصفحات
  final List<Widget> _pages = [
    const HomeScreen(),
    const Scaffold(body: Center(child: Text("Search Screen"))), // مؤقت
    const Scaffold(body: Center(child: Text("My Courses"))),    // مؤقت
    const Scaffold(body: Center(child: Text("Profile"))),       // مؤقت
  ];

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("User entered Main App Area");
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      
      // عرض الصفحة الحالية
      body: _pages[_currentIndex],

      // شريط التنقل السفلي المخصص
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary, // خلفية الشريط
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))), // حد علوي خفيف
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, LucideIcons.home, "Home"),
              _buildNavItem(1, LucideIcons.search, "Search"),
              _buildNavItem(2, LucideIcons.bookOpen, "My Learning"),
              _buildNavItem(3, LucideIcons.user, "Profile"),
            ],
          ),
        ),
      ),
    );
  }

  // عنصر التنقل الواحد
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: isSelected
            ? BoxDecoration(
                color: AppColors.accentYellow.withOpacity(0.1), // خلفية خفيفة عند التحديد
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppColors.accentYellow : AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.accentYellow : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
