import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import '../../data/models/course_model.dart'; // تأكد من استيراد الموديل الخاص بالكورس
import 'course_details_screen.dart';
import 'my_requests_screen.dart';
import 'teacher_profile_screen.dart';
import 'teacher/student_requests_screen.dart';

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
   
  // ✅ قائمة لتخزين الكورسات العشوائية
  List<dynamic> _randomCourses = []; 

  bool _isTeacher = false;

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
    _checkUserRole();
    _generateRandomCourses(); // ✅ توليد القائمة العشوائية عند بدء الشاشة

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

  // ✅ دالة لاختيار 5 كورسات عشوائية
  void _generateRandomCourses() {
    if (_allCourses.isNotEmpty) {
      // نأخذ نسخة من القائمة الأصلية حتى لا نعدل ترتيب البيانات الرئيسية
      var tempList = List.of(_allCourses);
      tempList.shuffle(); // ✅ خلط القائمة عشوائياً
      setState(() {
        _randomCourses = tempList.take(5).toList(); // ✅ أخذ أول 5 عناصر بعد الخلط
      });
    }
  }

  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ منطق العرض: إذا كان هناك بحث نستخدم _allCourses، وإلا نستخدم _randomCourses
    List<dynamic> coursesToDisplay;
     
    if (_searchTerm.isEmpty) {
      // إذا لم يكن هناك بحث، اعرض القائمة العشوائية التي جهزناها
      coursesToDisplay = _randomCourses;
      // حماية إضافية: إذا كانت القائمة العشوائية فارغة لسبب ما (مثل تحميل البيانات متأخراً)، أعد توليدها
      if (coursesToDisplay.isEmpty && _allCourses.isNotEmpty) {
         _generateRandomCourses();
         coursesToDisplay = _randomCourses;
      }
    } else {
      // إذا كان المستخدم يبحث، قم بالفلترة من القائمة الكاملة
      coursesToDisplay = _allCourses.where((course) => 
        course.title.toLowerCase().contains(_searchTerm.toLowerCase()) ||
        course.code.toLowerCase().contains(_searchTerm.toLowerCase())
      ).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header & Search Section ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                // 🔥 تم حذف const هنا
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
                          // 🔥 تم حذف const هنا
                          Text(
                            "WELCOME",
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 🔥 تم حذف const هنا
                          Text(
                            (_user?['first_name'] ?? "GUEST").toUpperCase(),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                       
                      // زر الطلبات
                      GestureDetector(
                        onTap: () {
                           if (_isTeacher) {
                             Navigator.push(
                               context, 
                               MaterialPageRoute(builder: (_) => const StudentRequestsScreen())
                             );
                           } else {
                             Navigator.push(
                               context, 
                               MaterialPageRoute(builder: (_) => const MyRequestsScreen())
                             );
                           }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          // 🔥 تم حذف const هنا
                          child: Icon(
                            _isTeacher ? LucideIcons.inbox : LucideIcons.clipboardList,
                            color: AppColors.accentYellow, 
                            size: 22
                          ),
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
                      // 🔥 تم حذف const هنا
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        // 🔥 تم حذف const هنا
                        prefixIcon: Icon(
                          LucideIcons.search, 
                          color: _searchTerm.isNotEmpty ? AppColors.accentYellow : AppColors.textSecondary,
                          size: 18,
                        ),
                        hintText: "Search course name or code...",
                        // 🔥 تم حذف const هنا
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
                              // 🔥 تم حذف const هنا
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
                                      // 🔥 تم حذف const هنا
                                      style: TextStyle(
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
                                      // 🔥 تم حذف const هنا
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
                      children: [
                        // 🔥 تم حذف const هنا
                        Text(
                          _searchTerm.isEmpty ? "SUGGESTED FOR YOU" : "SEARCH RESULTS", // ✅ تغيير العنوان حسب الحالة
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        // 🔥 تم حذف const هنا
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
                    coursesToDisplay.isEmpty 
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        // 🔥 تم حذف const هنا
                        child: Text("No courses found", style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5))),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: coursesToDisplay.length,
                        itemBuilder: (context, index) {
                          final course = coursesToDisplay[index];
                           
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
                                          // 🔥 تم حذف const هنا
                                          color: AppColors.accentOrange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          "#${course.code}",
                                          // 🔥 تم حذف const هنا
                                          style: TextStyle(
                                            color: AppColors.accentOrange,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                      // 🔥 تم حذف const هنا
                                      Icon(LucideIcons.chevronRight, color: AppColors.accentYellow, size: 20),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                   
                                  // Title
                                  Text(
                                    course.title.toUpperCase(),
                                    // 🔥 تم حذف const هنا
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Teacher info (CLICKABLE)
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
                                        // 🔥 تم حذف const هنا
                                        Icon(LucideIcons.userCircle, size: 14, color: AppColors.accentOrange),
                                        const SizedBox(width: 8),
                                        Text(
                                          course.instructorName.toUpperCase(),
                                          // 🔥 تم حذف const هنا
                                          style: TextStyle(
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
