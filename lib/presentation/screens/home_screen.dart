import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import 'course_details_screen.dart';
import 'my_requests_screen.dart';
import 'teacher_profile_screen.dart'; // ✅ تم تفعيل الاستيراد للتنقل لصفحة المدرس

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchTerm = "";
  int _currentSlide = 0;
  late Timer _timer;
  final PageController _pageController = PageController();

  // جلب البيانات من مدير الحالة المركزي
  final _allCourses = AppState().allCourses;
  final _user = AppState().userData;

  final List<String> _encouragements = [
    "Knowledge is the key to unlocking your true potential.",
    "Every expert was once a beginner. Keep learning.",
    "Your future self will thank you for the effort you put in today.",
    "Invest in yourself; education pays the best interest.",
    "Learning never exhausts the mind. Stay curious!"
  ];

  @override
  void initState() {
    super.initState();
    // إعداد مؤقت السلايدر للنص التشجيعي
    _timer = Timer.periodic(const Duration(seconds: 8), (Timer timer) {
      if (_currentSlide < _encouragements.length - 1) {
        _currentSlide++;
      } else {
        _currentSlide = 0;
      }
      
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentSlide,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // تصفية الكورسات محلياً بناءً على البحث
    final filteredCourses = _allCourses.where((course) => 
      course.title.toLowerCase().contains(_searchTerm.toLowerCase()) ||
      course.code.toLowerCase().contains(_searchTerm.toLowerCase())
    ).take(5).toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header & Search Section ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary.withOpacity(0.8),
                border: const Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "WELCOME",
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (_user?['first_name'] ?? "GUEST").toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      
                      // زر الطلبات السابقة
                      GestureDetector(
                        onTap: () {
                           Navigator.push(
                            context, 
                            MaterialPageRoute(builder: (_) => const MyRequestsScreen())
                          );
                        },
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: const Icon(LucideIcons.clipboardList, color: AppColors.accentYellow, size: 22),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppColors.accentOrange,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.backgroundSecondary, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: TextField(
                      onChanged: (val) => setState(() => _searchTerm = val),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          LucideIcons.search, 
                          color: _searchTerm.isNotEmpty ? AppColors.accentYellow : AppColors.textSecondary,
                          size: 18,
                        ),
                        hintText: "Search course name or code...",
                        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- Scrollable Content ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Slider
                    SizedBox(
                      height: 96,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 12, left: 16,
                              child: Icon(LucideIcons.quote, color: AppColors.backgroundSecondary.withOpacity(0.2), size: 32),
                            ),
                            PageView.builder(
                              controller: _pageController,
                              itemCount: _encouragements.length,
                              onPageChanged: (idx) => setState(() => _currentSlide = idx),
                              itemBuilder: (context, index) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 32),
                                    child: Text(
                                      _encouragements[index].toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.backgroundPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              bottom: 12,
                              left: 0, right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(_encouragements.length, (index) {
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    width: _currentSlide == index ? 20 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _currentSlide == index 
                                          ? AppColors.accentYellow 
                                          : AppColors.backgroundSecondary.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Section Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          "AVAILABLE COURSES",
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          "ACTIVE",
                          style: TextStyle(
                            color: AppColors.accentOrange,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Course List
                    filteredCourses.isEmpty 
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text("No courses found", style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5))),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredCourses.length,
                        itemBuilder: (context, index) {
                          final course = filteredCourses[index];
                          
                          return GestureDetector(
                            onTap: () {
                               Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CourseDetailsScreen(courseCode: course.code),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: ID and Chevron
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentOrange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          "#${course.code}",
                                          style: const TextStyle(
                                            color: AppColors.accentOrange,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                      const Icon(LucideIcons.chevronRight, color: AppColors.accentYellow, size: 20),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Title
                                  Text(
                                    course.title.toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // ✅ Teacher info (CLICKABLE)
                                  GestureDetector(
                                    onTap: () {
                                      if (course.teacherId.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => TeacherProfileScreen(teacherId: course.teacherId)
                                          ),
                                        );
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        const Icon(LucideIcons.userCircle, size: 14, color: AppColors.accentOrange),
                                        const SizedBox(width: 8),
                                        Text(
                                          course.instructorName.toUpperCase(),
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
