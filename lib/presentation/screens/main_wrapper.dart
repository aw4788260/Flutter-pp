import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'home_screen.dart';
import 'my_courses_screen.dart';
import 'profile_screen.dart';
// سنقوم بإنشاء هذه الشاشة لاحقاً، حالياً نستخدم Placeholder
class DownloadedFilesScreen extends StatelessWidget { const DownloadedFilesScreen({super.key}); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("Downloads"))); }

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const MyCoursesScreen(),
    const DownloadedFilesScreen(),
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
      // Custom Bottom Navigation matching BottomNav.tsx
      bottomNavigationBar: Container(
        height: 80, // h-20
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withOpacity(0.9), // bg-background-secondary/80
          border: const Border(
            top: BorderSide(color: Colors.white10), // border-white/10
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, LucideIcons.home, "Home"),
            _buildNavItem(1, LucideIcons.bookOpen, "Courses"),
            _buildNavItem(2, LucideIcons.download, "Downloads"),
            _buildNavItem(3, LucideIcons.user, "Profile"),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80, // w-20
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Top Indicator Line (Active State)
            if (isSelected)
              Positioned(
                top: 0,
                child: Container(
                  width: 48, // w-12
                  height: 4, // h-1
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentYellow.withOpacity(0.5),
                        blurRadius: 12,
                      )
                    ],
                  ),
                ),
              ),

            // Icon & Label
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8), // pt-2
                Icon(
                  icon,
                  size: 24,
                  color: isSelected ? AppColors.accentYellow : AppColors.textSecondary,
                ),
                const SizedBox(height: 6), // gap-1.5
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5, // tracking-widest
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
