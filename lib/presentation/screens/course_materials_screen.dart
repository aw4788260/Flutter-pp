import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import 'subject_materials_screen.dart';
import '../../core/services/storage_service.dart';
// أو المسار المناسب حسب مكان الملف

class CourseMaterialsScreen extends StatefulWidget {
  final String courseId;
  final String courseCode;
  final String courseTitle;
  final String? instructorName; // ✅ استقبال اسم المدرس
  final List<dynamic>? preLoadedSubjects; // ✅ استقبال المواد المحملة مسبقاً

  const CourseMaterialsScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    required this.courseCode,
    this.instructorName,
    this.preLoadedSubjects,
  });

  @override
  State<CourseMaterialsScreen> createState() => _CourseMaterialsScreenState();
}

class _CourseMaterialsScreenState extends State<CourseMaterialsScreen> {
  bool _loading = true;
  List<dynamic> _ownedSubjects = [];
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    // ✅ 1. استخدام البيانات الممررة (إذا وجدت) لتسريع الفتح وتقليل طلبات السيرفر
    if (widget.preLoadedSubjects != null && widget.preLoadedSubjects!.isNotEmpty) {
      _ownedSubjects = widget.preLoadedSubjects!;
      _loading = false;
    } else {
      // ✅ 2. وإلا نقوم بجلبها من السيرفر (للحالات النادرة)
      _fetchSubjects();
    }
  }

  Future<void> _fetchSubjects() async {
    try {
      var box = await StorageService.openBox('auth_box');
      // ✅ جلب التوكن والبصمة
      final String? token = box.get('jwt_token');
      final String? deviceId = box.get('device_id');

      final res = await Dio().get(
        '$_baseUrl/api/public/get-course-sales-details',
        queryParameters: {'courseCode': widget.courseCode},
        options: Options(headers: {
          if (token != null) 'Authorization': 'Bearer $token', // ✅ إرسال التوكن
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (mounted) {
        final data = res.data;
        final allSubjects = data['subjects'] as List;
        
        bool ownsCourse = AppState().ownsCourse(widget.courseId);

        setState(() {
          // فلترة المواد التي يملكها الطالب فقط
          _ownedSubjects = allSubjects.where((sub) {
            bool ownsSubject = AppState().ownsSubject(sub['id'].toString());
            return ownsCourse || ownsSubject;
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ استخدام اسم المدرس الممرر من الصفحة السابقة (Init Data)
    final String displayInstructor = widget.instructorName ?? "Instructor";

    // -------------------------------------------------------------------------
    // ✅ منطق الاستجابة لحجم الشاشة (Responsive Layout)
    // -------------------------------------------------------------------------
    final double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2; // الافتراضي للموبايل

    if (screenWidth > 900) {
      crossAxisCount = 4; // تابلت أفقي عريض
    } else if (screenWidth > 600) {
      crossAxisCount = 3; // تابلت رأسي أو موبايل كبير جداً
    }
    // -------------------------------------------------------------------------

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ✅ Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.courseTitle.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            overflow: TextOverflow.ellipsis,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "CHOOSE SUBJECT",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentYellow,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ✅ Content Area
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
                  : _ownedSubjects.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.layers, size: 40, color: AppColors.textSecondary.withOpacity(0.5)),
                              const SizedBox(height: 16),
                              Text(
                                "NO SUBJECTS FOUND",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary.withOpacity(0.5),
                                  letterSpacing: 2.0,
                                ),
                              )
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount, // ✅ استخدام العدد الديناميكي
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: _ownedSubjects.length,
                          itemBuilder: (context, index) {
                            final subject = _ownedSubjects[index];
                            
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SubjectMaterialsScreen(
                                      subjectId: subject['id'].toString(), 
                                      subjectTitle: subject['title']
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // أيقونة التشغيل العلوية
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          width: 8, height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.accentOrange,
                                            shape: BoxShape.circle,
                                            boxShadow: [BoxShadow(color: AppColors.accentOrange, blurRadius: 4)],
                                          ),
                                        ),
                                        const Icon(LucideIcons.playCircle, size: 20, color: AppColors.accentOrange),
                                      ],
                                    ),

                                    // اسم المادة
                                    Text(
                                      subject['title'].toString().toUpperCase(),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                        height: 1.1,
                                        letterSpacing: -0.5,
                                      ),
                                    ),

                                    // اسم المدرس والسهم
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // ✅ عرض اسم المدرس هنا بشكل صحيح
                                              Text(
                                                displayInstructor.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.textSecondary.withOpacity(0.7),
                                                  letterSpacing: 1.5,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                height: 2, width: 24,
                                                decoration: BoxDecoration(
                                                  color: AppColors.accentOrange.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(1),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          width: 24, height: 24,
                                          decoration: const BoxDecoration(
                                            color: AppColors.backgroundPrimary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(LucideIcons.chevronRight, size: 14, color: AppColors.accentOrange),
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
