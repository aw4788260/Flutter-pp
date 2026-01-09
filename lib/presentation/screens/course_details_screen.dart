import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'checkout_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');

      final res = await Dio().get(
        '$_baseUrl/api/public/get-course-sales-details',
        queryParameters: {'courseCode': widget.courseCode},
        options: Options(headers: {
    'x-user-id': userId,
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
    final subjects = List<Map<String, dynamic>>.from(course['subjects'] ?? []);
    final double fullPrice = (course['price'] ?? 0).toDouble();

    // ✅ منطق جديد: التحقق مما إذا كانت جميع المواد مملوكة
    bool allSubjectsOwned = false;
    if (subjects.isNotEmpty) {
      allSubjectsOwned = subjects.every((s) => s['isOwned'] == true);
    }

    // ✅ اعتبار الكورس مملوكاً إذا تم شراؤه كحزمة أو تم شراء جميع مواده
    bool isCourseOwned = (course['isOwned'] ?? false) || allSubjectsOwned;

    // حساب السعر الإجمالي
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
                      const SizedBox(height: 12),
                      
                      // Instructor
                      Row(
                        children: [
                          const Icon(LucideIcons.userCircle, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            teacher['name'] ?? "Unknown Instructor",
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      Text(
                        course['description'] ?? "No description available.",
                        style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), height: 1.6, fontSize: 14),
                      ),
                      
                      const SizedBox(height: 40),
                      const Text("PURCHASE OPTIONS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentYellow, letterSpacing: 2.0)),
                      const SizedBox(height: 20),

                      // 1. Full Course Option (يظهر فقط إذا لم يكن مملوكاً بالكامل)
                      if (!isCourseOwned) // ✅ تم استخدام المتغير الجديد هنا
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
                        // ✅ رسالة تظهر إذا كان الكورس مملوكاً
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
                            onTap: (isOwned || isCourseOwned) ? null : () { // ✅ منع الاختيار إذا كان الكورس مملوكاً
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
                    ],
                  ),
                ),
              ),
            ],
          ),

          // --- Bottom Checkout Bar ---
          if (currentPrice > 0)
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
                        // تجهيز العناصر المختارة
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
                        
                        // الانتقال للدفع
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
