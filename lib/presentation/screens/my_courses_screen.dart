import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
// ✅ إضافة استيراد خدمة المدرس
import '../../core/services/teacher_service.dart';
import 'course_details_screen.dart';
import 'course_materials_screen.dart';
import 'login_screen.dart';
import 'teacher/manage_content_screen.dart';

class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key});

  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  String _view = 'library'; // library | market
  String _searchTerm = '';
  bool _isTeacher = false;
  bool _isUpdating = false;
  
  // ✅ تعريف خدمة المدرس
  final TeacherService _teacherService = TeacherService();

  @override
  void initState() {
    super.initState();
    _checkUserRole();
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

  // ✅ منطق التحديث المعدل (الحل الجذري للمشكلة)
  Future<void> _refreshData() async {
    if (mounted) setState(() => _isUpdating = true); // إظهار التحميل فوراً

    try {
      // 1. إذا كان المستخدم مدرساً، نجبر التطبيق على جلب أحدث محتوى له من السيرفر وتحديث الكاش
      if (_isTeacher) {
        try {
          final updatedContent = await _teacherService.getMyContent();
          var box = await StorageService.openBox('teacher_data');
          await box.put('my_content', updatedContent);
        } catch (e) {
          debugPrint("Failed to refresh teacher content: $e");
        }
      }

      // 2. إعادة تحميل حالة التطبيق العامة (والتي ستقرأ الآن الكاش المحدث)
      await AppState().reloadAppInit();

    } catch (e) {
      debugPrint("Error refreshing data: $e");
    } finally {
      // 3. إخفاء التحميل وإعادة بناء الواجهة
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppState().isGuest) {
      if (_view == 'market') {
        return _buildMarketView();
      }
      return _buildGuestView();
    }

    if (_view == 'market') {
      return _buildMarketView();
    }
    return _buildLibraryView();
  }

  // --- 2. واجهة خاصة بالضيف ---
  Widget _buildGuestView() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: const Icon(LucideIcons.lock, color: AppColors.textSecondary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "LIBRARY",
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              height: 1.0,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "GUEST MODE",
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // زر الذهاب للمتجر
                  GestureDetector(
                    onTap: () => setState(() => _view = 'market'),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(LucideIcons.shoppingCart, color: AppColors.accentYellow, size: 22),
                    ),
                  ),
                ],
              ),
            ),

            // Login Required Message
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.shieldAlert, size: 64, color: AppColors.textSecondary.withOpacity(0.2)),
                    const SizedBox(height: 24),
                    const Text(
                      "LOGIN REQUIRED",
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Sign in to access your purchased lessons.",
                      style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 12),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        "LOGIN NOW",
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
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

  // --- 3. واجهة المكتبة ---
  Widget _buildLibraryView() {
    // استخدام البيانات من الحالة العامة
    final libraryItems = AppState().myLibrary;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: const Icon(LucideIcons.bookOpen, color: AppColors.accentYellow, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "LIBRARY",
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              height: 1.0,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "MY LESSONS",
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Buttons
                  Row(
                    children: [
                      // 🟢 زر إضافة كورس (للمدرس)
                      if (_isTeacher) ...[
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManageContentScreen(contentType: ContentType.course),
                              ),
                            ).then((value) {
                              // ✅ عند العودة بنجاح (value == true)، نقوم بالتحديث
                              if (value == true) {
                                _refreshData();
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(color: AppColors.accentYellow.withOpacity(0.5)),
                            ),
                            child: const Icon(LucideIcons.plusSquare, color: AppColors.accentYellow, size: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // زر المتجر
                      GestureDetector(
                        onTap: () => setState(() => _view = 'market'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: const Icon(LucideIcons.shoppingCart, color: AppColors.accentYellow, size: 22),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            if (_isUpdating)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accentYellow),
                ),
              )
            else
              Expanded(
                child: libraryItems.isEmpty
                    ? Center(
                        child: Text(
                          "NO ACTIVE COURSES",
                          style: TextStyle(
                            color: AppColors.textSecondary.withOpacity(0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: libraryItems.length,
                        itemBuilder: (context, index) {
                          final item = libraryItems[index];
                          
                          final String title = item['title'] ?? 'Unknown';
                          final String instructor = item['instructor'] ?? 'Instructor';
                          final String code = item['code']?.toString() ?? '';
                          final String id = item['id'].toString();
                          
                          final String description = item['description'] ?? '';
                          final double localPrice = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;

                          List<dynamic>? subjectsToPass;
                          if (item['owned_subjects'] is List) {
                            subjectsToPass = item['owned_subjects'];
                          }

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CourseMaterialsScreen(
                                    courseId: id,
                                    courseTitle: title,
                                    courseCode: code,
                                    instructorName: instructor, 
                                    preLoadedSubjects: subjectsToPass, 
                                  ),
                                ),
                              ).then((updatedSubjects) {
                                if (updatedSubjects != null && updatedSubjects is List) {
                                  final index = AppState().myLibrary.indexWhere((c) => c['id'].toString() == id);
                                  if (index != -1) {
                                    AppState().myLibrary[index]['owned_subjects'] = updatedSubjects;
                                    if (mounted) setState(() {});
                                  }
                                }
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundPrimary,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                    ),
                                    child: const Icon(
                                      LucideIcons.playCircle, 
                                      color: AppColors.accentOrange, 
                                      size: 24
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (code.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(bottom: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.accentOrange.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppColors.accentOrange.withOpacity(0.2), width: 0.5),
                                            ),
                                            child: Text(
                                              "#$code",
                                              style: const TextStyle(
                                                color: AppColors.accentOrange,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),

                                        Text(
                                          title.toUpperCase(),
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -0.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              instructor.toUpperCase(),
                                              style: TextStyle(
                                                color: AppColors.textSecondary.withOpacity(0.7),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // 🟢 زر التعديل (داخل البطاقة)
                                  if (_isTeacher)
                                    GestureDetector(
                                      onTap: () {
                                        double realPrice = localPrice;
                                        try {
                                          final freshCourse = AppState().allCourses.firstWhere((c) => c.id == id);
                                          realPrice = freshCourse.fullPrice;
                                        } catch (_) {}

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ManageContentScreen(
                                              contentType: ContentType.course,
                                              initialData: {
                                                'id': id,
                                                'title': title,
                                                'code': code,
                                                'price': realPrice,
                                                'fullPrice': realPrice,
                                                'description': description,
                                              },
                                            ),
                                          ),
                                        ).then((value) {
                                          if (value == true) {
                                            _refreshData();
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentYellow.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.accentYellow.withOpacity(0.3)),
                                        ),
                                        child: const Icon(LucideIcons.edit3, color: AppColors.accentYellow, size: 18),
                                      ),
                                    )
                                  else
                                    Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withOpacity(0.6), size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 4. واجهة المتجر ---
  Widget _buildMarketView() {
    final availableCourses = AppState().allCourses.where((course) => 
      course.title.toLowerCase().contains(_searchTerm.toLowerCase()) ||
      course.code.toLowerCase().contains(_searchTerm.toLowerCase())
    ).toList();

    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth >= 600) crossAxisCount = 3;
    if (screenWidth >= 900) crossAxisCount = 4;
    if (screenWidth >= 1200) crossAxisCount = 5;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _view = 'library'),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "MARKET",
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: TextField(
                  autofocus: false,
                  onChanged: (val) => setState(() => _searchTerm = val),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 18,
                      color: _searchTerm.isNotEmpty ? AppColors.accentYellow : AppColors.textSecondary,
                    ),
                    hintText: "Find excellence...",
                    hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
                itemCount: availableCourses.length,
                itemBuilder: (context, index) {
                  final course = availableCourses[index];

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
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Icon(LucideIcons.compass, size: 14, color: AppColors.accentYellow),
                              Icon(LucideIcons.shoppingCart, size: 14, color: AppColors.textSecondary.withOpacity(0.4)),
                            ],
                          ),
                          Text(
                            course.title.toUpperCase(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                course.instructorName.toUpperCase(),
                                style: TextStyle(
                                  color: AppColors.textSecondary.withOpacity(0.7),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${course.fullPrice.toInt()} EGP", 
                                style: const TextStyle(
                                  color: AppColors.accentYellow,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
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
            ),
          ],
        ),
      ),
    );
  }
}
