import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/mock_data.dart';
import 'course_details_screen.dart';
// import 'my_requests_screen.dart'; // سننشئها لاحقاً

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
    // Slider Timer (8 seconds)
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
    // Filter courses logic
    final filteredCourses = mockCourses.where((course) => 
      course.title.toLowerCase().contains(_searchTerm.toLowerCase()) ||
      course.id.toLowerCase().contains(_searchTerm.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header & Search (Sticky Effect via Container) ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary.withOpacity(0.8), // backdrop-blur equivalent
                border: const Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                children: [
                  // Top Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "WELCOME",
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "AHMED WALID", // Mock User
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      // My Requests Button
                      Stack(
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
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(16), // m3-xl
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
                        hintText: "Search course name or code (ID)...",
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
                    // Encouragement Slider
                    SizedBox(
                      height: 96, // h-24
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300], // bg-gray-300 from React code
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
                            // Indicators
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
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredCourses.length,
                      itemBuilder: (context, index) {
                        final course = filteredCourses[index];
                        final teacher = mockTeachers.firstWhere((t) => t.id == course.teacherId);
                        
                        return GestureDetector(
                          onTap: () {
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CourseDetailsScreen(),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                                        "#${course.id.toUpperCase()}",
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

                                // Teacher info
                                Row(
                                  children: [
                                    const Icon(LucideIcons.userCircle, size: 14, color: AppColors.accentOrange),
                                    const SizedBox(width: 8),
                                    Text(
                                      teacher.name.toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
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
