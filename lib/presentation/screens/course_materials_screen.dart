import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import 'subject_materials_screen.dart';

class CourseMaterialsScreen extends StatefulWidget {
  final String courseId;
  final String courseCode;
  final String courseTitle;
  // ✅ متغير جديد لاستقبال المواد المحملة مسبقاً
  final List<dynamic>? preLoadedSubjects;

  const CourseMaterialsScreen({
    super.key, 
    required this.courseId, 
    required this.courseTitle, 
    required this.courseCode,
    this.preLoadedSubjects, // ✅
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
    
    // ✅ التحقق: هل لدينا بيانات جاهزة؟
    if (widget.preLoadedSubjects != null && widget.preLoadedSubjects!.isNotEmpty) {
      _ownedSubjects = widget.preLoadedSubjects!;
      _loading = false;
    } else {
      // إذا لم تتوفر (مثلاً كورس كامل لم يتم جلب تفاصيله)، نقوم بالتحميل
      _fetchSubjects();
    }
  }

  Future<void> _fetchSubjects() async {
    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');

      final res = await Dio().get(
        '$_baseUrl/api/public/get-course-sales-details',
        queryParameters: {'courseCode': widget.courseCode},
        options: Options(headers: {'x-user-id': userId}),
      );

      if (mounted) {
        final data = res.data;
        final allSubjects = data['subjects'] as List;
        
        bool ownsCourse = AppState().ownsCourse(widget.courseId);

        setState(() {
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
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
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
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "SELECT A SUBJECT",
                          style: TextStyle(fontSize: 10, color: AppColors.accentYellow, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // --- Subjects List ---
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
                  : _ownedSubjects.isEmpty
                      ? const Center(child: Text("No owned subjects", style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(24),
                          itemCount: _ownedSubjects.length,
                          itemBuilder: (context, index) {
                            final subject = _ownedSubjects[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => SubjectMaterialsScreen(
                                    subjectId: subject['id'].toString(), 
                                    subjectTitle: subject['title']
                                  )),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        subject['title'],
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.backgroundPrimary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(LucideIcons.play, color: AppColors.accentOrange, size: 14),
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
