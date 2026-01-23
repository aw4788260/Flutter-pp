import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import 'subject_materials_screen.dart';
import 'teacher/manage_content_screen.dart'; 

class CourseMaterialsScreen extends StatefulWidget {
  final String courseId;
  final String courseCode;
  final String courseTitle;
  final String? instructorName;
  final List<dynamic>? preLoadedSubjects;

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
  bool _isTeacher = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    
    // 1. استخدام البيانات الممررة (إذا وجدت) لتسريع الفتح
    if (widget.preLoadedSubjects != null && widget.preLoadedSubjects!.isNotEmpty) {
      _ownedSubjects = widget.preLoadedSubjects!;
      _loading = false;
    } else {
      // 2. وإلا نقوم بجلبها من السيرفر
      _fetchSubjects();
    }
  }

  // ✅ التحقق من الصلاحية (هل هو معلم؟)
  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
      });
    }
  }

  Future<void> _fetchSubjects() async {
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
        final data = res.data;
        final allSubjects = data['subjects'] as List;
        
        bool ownsCourse = AppState().ownsCourse(widget.courseId);

        setState(() {
          _ownedSubjects = allSubjects.where((sub) {
            if (_isTeacher) return true; // ✅ المعلم يرى كل المواد
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
    final String displayInstructor = widget.instructorName ?? "Instructor";

    // --- Responsive Logic ---
    final double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2; 

    if (screenWidth > 900) {
      crossAxisCount = 4;
    } else if (screenWidth > 600) {
      crossAxisCount = 3;
    }

    // ✅ تغليف Scaffold بـ WillPopScope لإرجاع البيانات المحدثة عند الخروج
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _ownedSubjects);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: SafeArea(
          child: Column(
            children: [
              // --- Header ---
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            // ✅ إرجاع البيانات عند الضغط على زر الرجوع
                            Navigator.pop(context, _ownedSubjects);
                          },
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.courseTitle.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                      ],
                    ),

                    // 🟢 زر إضافة مادة (يظهر للمعلم فقط)
                    if (_isTeacher)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageContentScreen(
                                contentType: ContentType.subject,
                                parentId: widget.courseId, // تمرير ID الكورس كأب للمادة
                              ),
                            ),
                          ).then((value) {
                            // ✅ إعادة طلب البيانات عند نجاح الإضافة
                            if(value == true) {
                              setState(() => _loading = true);
                              _fetchSubjects(); 
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.accentYellow.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: AppColors.accentYellow.withOpacity(0.5)),
                          ),
                          child: const Icon(LucideIcons.plus, color: AppColors.accentYellow, size: 22),
                        ),
                      ),
                  ],
                ),
              ),

              // --- Content Area ---
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
                              crossAxisCount: crossAxisCount,
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
                                          
                                          // 🟢 أيقونة التعديل (للمعلم) أو أيقونة التشغيل (للطالب)
                                          if (_isTeacher)
                                            GestureDetector(
                                              onTap: () {
                                                // فتح شاشة التعديل للمادة
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => ManageContentScreen(
                                                      contentType: ContentType.subject,
                                                      initialData: subject,
                                                      parentId: widget.courseId,
                                                    ),
                                                  ),
                                                ).then((val) {
                                                  // ✅ إعادة طلب البيانات عند نجاح التعديل
                                                  if(val == true) {
                                                    setState(() => _loading = true);
                                                    _fetchSubjects();
                                                  }
                                                });
                                              },
                                              child: const Icon(LucideIcons.edit2, size: 20, color: AppColors.accentYellow),
                                            )
                                          else
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
      ),
    );
  }
}
