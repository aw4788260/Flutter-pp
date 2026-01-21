import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 
import '../../core/constants/app_colors.dart';
import 'chapter_contents_screen.dart';
import 'exam_view_screen.dart';
import 'exam_result_screen.dart'; 

class SubjectMaterialsScreen extends StatefulWidget {
  final String subjectId;
  final String subjectTitle;

  const SubjectMaterialsScreen({
    super.key,
    required this.subjectId,
    required this.subjectTitle,
  });

  @override
  State<SubjectMaterialsScreen> createState() => _SubjectMaterialsScreenState();
}

class _SubjectMaterialsScreenState extends State<SubjectMaterialsScreen> {
  String _activeTab = 'chapters'; // chapters | exams
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _content;
  
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Opened Subject: ${widget.subjectTitle} (${widget.subjectId})");
    _fetchContent();
  }

  Future<void> _fetchContent() async {
    try {
      var box = await Hive.openBox('auth_box');
      // ✅ جلب التوكن والبصمة
      final String? token = box.get('jwt_token');
      final String? deviceId = box.get('device_id');

      final res = await Dio().get(
        '$_baseUrl/api/secure/get-subject-content',
        queryParameters: {'subjectId': widget.subjectId},
        options: Options(headers: {
          'Authorization': 'Bearer $token', // ✅ الهيدر الجديد
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (mounted) {
        setState(() {
          _content = res.data;
          _loading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Fetching Subject Content Failed');
      if (mounted) setState(() { _error = "Failed to load content."; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_error != null) return Scaffold(backgroundColor: AppColors.backgroundPrimary, appBar: AppBar(backgroundColor: Colors.transparent, leading: const BackButton(color: AppColors.accentYellow)), body: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))));

    final chapters = _content!['chapters'] as List;
    final exams = _content!['exams'] as List;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
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
                              widget.subjectTitle.toUpperCase(),
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
                              "SUBJECT CONTENTS",
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
                  const SizedBox(height: 24),
                  
                  // Tab Switcher
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Row(
                      children: [
                        _buildTab("Chapters", 'chapters'),
                        _buildTab("Exams (${exams.length})", 'exams'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: _activeTab == 'chapters'
                  ? _buildChaptersList(chapters)
                  : _buildExamsList(exams),
            ),
          ],
        ),
      ),
    );
  }

  // --- قائمة الامتحانات ---
  Widget _buildExamsList(List exams) {
    if (exams.isEmpty) return _buildEmptyState(LucideIcons.fileCheck, "No exams available");

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: exams.length,
      itemBuilder: (context, index) {
        final exam = exams[index];
        final bool isCompleted = exam['isCompleted'] ?? false;

        final Color statusColor = isCompleted ? AppColors.success : AppColors.error;
        final String statusText = isCompleted ? "COMPLETED" : "UNSOLVED";

        return GestureDetector(
          onTap: () {
             if (isCompleted) {
               // محاولة الحصول على معرف المحاولة (سواء كانت الأولى أو الأخيرة)
               final attemptId = exam['last_attempt_id'] ?? exam['first_attempt_id'] ?? exam['attempt_id']; 
               
               if (attemptId != null) {
                 Navigator.push(
                   context,
                   MaterialPageRoute(
                     builder: (_) => ExamResultScreen(
                       attemptId: attemptId.toString(),
                       examTitle: exam['title'] ?? 'Exam Result',
                     ),
                   ),
                 );
               } else {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text("Error: Cannot load result (No Attempt ID found)."), backgroundColor: AppColors.error)
                 );
               }
             } else {
               Navigator.push(
                 context,
                 MaterialPageRoute(builder: (_) => ExamViewScreen(
                   examId: exam['id'].toString(),
                   examTitle: exam['title'] ?? 'Exam',
                   isCompleted: isCompleted,
                 )),
               );
             }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Icon(
                    isCompleted ? LucideIcons.checkCircle2 : LucideIcons.fileX, 
                    color: statusColor, 
                    size: 20
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (exam['title'] ?? 'Untitled Exam').toString().toUpperCase(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            "${exam['duration_minutes'] ?? 0} MINS",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary.withOpacity(0.7),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 20, color: statusColor.withOpacity(0.5)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChaptersList(List chapters) {
    if (chapters.isEmpty) return _buildEmptyState(LucideIcons.bookOpen, "No chapters found");

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final videosCount = (chapter['videos'] as List? ?? []).length;
        final pdfsCount = (chapter['pdfs'] as List? ?? []).length;

        return GestureDetector(
          onTap: () {
            // ✅ قراءة اسم الكورس من الاستجابة (أصبح متاحاً الآن بعد تعديل الـ API)
            final String courseTitle = _content?['course_title'] ?? 'Unknown Course';
            
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChapterContentsScreen(
                  chapter: Map<String, dynamic>.from(chapter),
                  // ✅ تمرير الهيكل الشجري الكامل للشاشة التالية
                  courseTitle: courseTitle,
                  subjectTitle: widget.subjectTitle,
                )
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                  ),
                  child: Center(
                    child: Text(
                      "${index + 1}".padLeft(2, '0'),
                      style: const TextStyle(
                        color: AppColors.accentYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (chapter['title'] ?? 'Chapter').toString().toUpperCase(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(LucideIcons.hash, size: 10, color: AppColors.accentOrange),
                          const SizedBox(width: 4),
                          Text(
                            "${videosCount + pdfsCount} CONTENTS",
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTab(String title, String key) {
    final isActive = _activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeTab = key);
          FirebaseCrashlytics.instance.log("Switched tab to: $key");
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.backgroundPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: isActive ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
          ),
          child: Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isActive ? AppColors.accentYellow : AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
