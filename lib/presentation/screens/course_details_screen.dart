import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'checkout_screen.dart';
import 'teacher_profile_screen.dart'; 
import '../../core/services/storage_service.dart';

class CourseDetailsScreen extends StatefulWidget {
  final String courseCode;
  const CourseDetailsScreen({super.key, required this.courseCode});

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _courseData;
  List<String> _selectedSubjectIds = [];
  bool _isFullCourse = false;
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';
  
  bool _isTeacher = false; // ✅ متغير لحفظ الدور

  @override
  void initState() {
    super.initState();
    _checkUserRole(); // ✅ التحقق من الدور
    _fetchDetails();
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

  Future<void> _fetchDetails() async {
    try {
      var box = await StorageService.openBox('auth_box');
      final String? token = box.get('jwt_token');
      final String? deviceId = box.get('device_id');

      final res = await Dio().get(
        '$_baseUrl/api/public/get-course-sales-details',
        queryParameters: {'courseCode': widget.courseCode},
        options: Options(headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (mounted) {
        setState(() {
          _courseData = res.data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_courseData == null) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: Text("Course not found", style: TextStyle(color: Colors.white))));

    final course = _courseData!;
    final teacher = course['teacher'] ?? {};
    final String teacherName = teacher['name'] ?? "Unknown Instructor";
    final String? teacherId = teacher['id']?.toString(); 

    final subjects = List<Map<String, dynamic>>.from(course['subjects'] ?? []);
    final double fullPrice = (course['price'] ?? 0).toDouble();

    bool allSubjectsOwned = false;
    if (subjects.isNotEmpty) {
      allSubjectsOwned = subjects.every((s) => s['isOwned'] == true);
    }

    bool isCourseOwned = (course['isOwned'] ?? false) || allSubjectsOwned;

    double currentPrice = _isFullCourse 
        ? fullPrice 
        : subjects.where((s) => _selectedSubjectIds.contains(s['id'].toString())).fold(0, (sum, s) => sum + (s['price'] ?? 0));

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header & Back
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Title & Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "#${course['code']}",
                          style: const TextStyle(color: AppColors.accentOrange, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        course['title'].toString().toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // ✅ تصميم جديد وأنيق لبطاقة المدرس (New Elegant Instructor Card)
                      GestureDetector(
                        onTap: () {
                          if (teacherId != null && teacherId.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TeacherProfileScreen(teacherId: teacherId),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Instructor profile not available")),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min, // تأخذ حجم المحتوى فقط
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundPrimary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.accentOrange.withOpacity(0.5)),
                                ),
                                child: const Icon(LucideIcons.user, color: AppColors.accentOrange, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "INSTRUCTOR",
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    teacherName,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      Text(
                        course['description'] ?? "No description available.",
                        style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), height: 1.6, fontSize: 14),
                      ),
                      
                      const SizedBox(height: 40),

                      // ✅ إذا كان المستخدم مدرساً: إخفاء خيارات الشراء وعرض رسالة
                      if (_isTeacher) 
                        Container(
                          padding: const EdgeInsets.all(24),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: const [
                              Icon(LucideIcons.lock, color: AppColors.textSecondary, size: 32),
                              SizedBox(height: 12),
                              Text(
                                "TEACHER ACCOUNT",
                                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Teachers cannot purchase courses.",
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else ...[
                        // الكود الأصلي لخيارات الشراء (يظهر فقط للطلاب)
                        const Text("PURCHASE OPTIONS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentYellow, letterSpacing: 2.0)),
                        const SizedBox(height: 20),

                        // 1. Full Course Option
                        if (!isCourseOwned) 
                          GestureDetector(
                            onTap: () => setState(() { _isFullCourse = !_isFullCourse; _selectedSubjectIds.clear(); }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isFullCourse ? AppColors.accentYellow : Colors.white.withOpacity(0.05),
                                  width: _isFullCourse ? 2 : 1,
                                ),
                                boxShadow: _isFullCourse ? [BoxShadow(color: AppColors.accentYellow.withOpacity(0.2), blurRadius: 15)] : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("FULL COURSE ACCESS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text("Access all subjects & exams", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                                    ],
                                  ),
                                  Text("$fullPrice EGP", style: const TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.w900, fontSize: 18)),
                                ],
                              ),
                            ),
                          )
                        else 
                          Container(
                            padding: const EdgeInsets.all(24),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.success.withOpacity(0.5)),
                            ),
                            child: Column(
                              children: const [
                                Icon(LucideIcons.checkCircle, color: AppColors.success, size: 32),
                                SizedBox(height: 8),
                                Text("COURSE OWNED", style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                              ],
                            ),
                          ),

                        if (subjects.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          const Text("INDIVIDUAL SUBJECTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0)),
                          const SizedBox(height: 16),
                          
                          // 2. Individual Subjects List
                          ...subjects.map((sub) {
                            bool isOwned = sub['isOwned'] ?? false;
                            bool isSelected = _selectedSubjectIds.contains(sub['id'].toString());
                            
                            return GestureDetector(
                              onTap: (isOwned || isCourseOwned) ? null : () {
                                setState(() {
                                  _isFullCourse = false;
                                  if (isSelected) {
                                    _selectedSubjectIds.remove(sub['id'].toString());
                                  } else {
                                    _selectedSubjectIds.add(sub['id'].toString());
                                  }
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected ? AppColors.accentOrange : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    if (!isOwned && !isCourseOwned)
                                      Container(
                                        margin: const EdgeInsets.only(right: 16),
                                        width: 20, height: 20,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: isSelected ? AppColors.accentOrange : Colors.white24, width: 2),
                                          color: isSelected ? AppColors.accentOrange : Colors.transparent,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        sub['title'],
                                        style: TextStyle(
                                          color: (isOwned || isCourseOwned) ? AppColors.textSecondary : Colors.white,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          decoration: (isOwned || isCourseOwned) ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                    ),
                                    if (isOwned || isCourseOwned)
                                      const Text("OWNED", style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold))
                                    else
                                      Text("${sub['price']} EGP", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ], // نهاية الشرط (else)
                    ],
                  ),
                ),
              ),
            ],
          ),

          // --- Bottom Checkout Bar ---
          // ✅ إخفاء الشريط السفلي تماماً إذا كان المستخدم مدرساً
          if (currentPrice > 0 && !_isTeacher)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, -5))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("TOTAL PAYABLE", style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text("$currentPrice EGP", style: const TextStyle(color: AppColors.accentYellow, fontSize: 24, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                        List<Map<String, dynamic>> selectedItems = [];
                        if (_isFullCourse) {
                          selectedItems.add({'id': course['id'], 'type': 'course', 'title': course['title'], 'price': fullPrice});
                        } else {
                          for (var sub in subjects) {
                            if (_selectedSubjectIds.contains(sub['id'].toString())) {
                              selectedItems.add({'id': sub['id'], 'type': 'subject', 'title': sub['title'], 'price': sub['price']});
                            }
                          }
                        }
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CheckoutScreen(
                              amount: currentPrice,
                              paymentInfo: Map<String, dynamic>.from(course['paymentInfo'] ?? {}),
                              selectedItems: selectedItems,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Row(
                        children: const [
                          Text("CHECKOUT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0)),
                          SizedBox(width: 8),
                          Icon(LucideIcons.arrowRight, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
