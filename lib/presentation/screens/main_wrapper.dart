import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'home_screen.dart';
import 'my_courses_screen.dart';
import 'downloaded_files_screen.dart';
import 'profile_screen.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const MyCoursesScreen(),
    const DownloadedFilesScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8), // مسافة للأزرار
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.accentYellow,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0),
          items: const [
            BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: "HOME"),
            BottomNavigationBarItem(icon: Icon(LucideIcons.bookOpen), label: "LIBRARY"),
            BottomNavigationBarItem(icon: Icon(LucideIcons.downloadCloud), label: "DOWNLOADS"),
            BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: "PROFILE"),
          ],
        ),
      ),
    );
  }
}
