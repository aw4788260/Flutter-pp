import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/download_manager.dart'; // ✅ استيراد مدير التحميل
import 'video_player_screen.dart';
import 'exam_view_screen.dart';
import 'pdf_viewer_screen.dart'; // تأكد من وجوده

class SubjectMaterialsScreen extends StatefulWidget {
  final String subjectId;
  final String subjectTitle;

  // قمنا بتغيير المعاملات لتناسب الـ API بدلاً من الموديلات القديمة
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
    _fetchContent();
  }

  // --- جلب المحتوى ---
  Future<void> _fetchContent() async {
    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      final res = await Dio().get(
        '$_baseUrl/api/secure/get-subject-content',
        queryParameters: {'subjectId': widget.subjectId},
        options: Options(headers: {'x-user-id': userId, 'x-device-id': deviceId}),
      );

      if (mounted) {
        setState(() {
          _content = res.data;
          _loading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Fetching Subject Content: ID ${widget.subjectId}');
      if (mounted) setState(() { _error = "Failed to load content."; _loading = false; });
    }
  }

  // --- تشغيل الفيديو ---
  Future<void> _playVideo(Map<String, dynamic> video) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));

    try {
      var box = await Hive.openBox('auth_box');
      final res = await Dio().get(
        '$_baseUrl/api/secure/get-video-id',
        queryParameters: {'lessonId': video['id'].toString()}, 
        options: Options(headers: {'x-user-id': box.get('user_id'), 'x-device-id': box.get('device_id')}),
      );

      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = res.data;
        Map<String, String> qualities = {};
        if (data['availableQualities'] != null) {
          for (var q in data['availableQualities']) qualities["${q['quality']}p"] = q['url'];
        }
        if (qualities.isEmpty && data['url'] != null) qualities["Auto"] = data['url'];

        if (qualities.isNotEmpty && mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(streams: qualities, title: data['db_video_title'] ?? video['title'])));
        } else {
          _showError("No playable stream found.");
        }
      } else {
        _showError(res.data['message'] ?? "Access Denied");
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context);
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Play Video Failed');
      _showError("Connection Error");
    }
  }

  // --- التحميل ---
  void _startDownload(String videoId, String videoTitle, String chapterName) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preparing Download...")));
    DownloadManager().startDownload(
      lessonId: videoId,
      videoTitle: videoTitle,
      courseName: "My Courses",
      subjectName: widget.subjectTitle,
      chapterName: chapterName,
      onProgress: (p) {},
      onComplete: () { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Completed!"), backgroundColor: AppColors.success)); },
      onError: (e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download Failed: $e"), backgroundColor: AppColors.error)); },
    );
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));

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
            // Header Section (Original Design)
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
                              "SUBJECT CONTENTS", // استبدلنا اسم الكورس بنص عام أو يمكن جلبه
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentYellow,
                                letterSpacing: 2.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Tab Switcher (Original Design)
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
                  ? ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: chapters.length,
                      itemBuilder: (context, index) {
                        final chapter = chapters[index];
                        final videos = chapter['videos'] as List;
                        final pdfs = chapter['pdfs'] as List;
                        final totalItems = videos.length + pdfs.length;

                        // Chapter Item (Expandable Logic moved to detail view in original design, here we list items)
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Chapter Title Row
                              Row(
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
                                        style: const TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          chapter['title'].toString().toUpperCase(),
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(LucideIcons.hash, size: 10, color: AppColors.accentOrange),
                                            const SizedBox(width: 4),
                                            Text(
                                              "$totalItems CONTENTS",
                                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              
                              if (totalItems > 0) ...[
                                const SizedBox(height: 16),
                                const Divider(color: Colors.white10),
                                const SizedBox(height: 8),
                                
                                // Videos
                                ...videos.map((v) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(LucideIcons.playCircle, size: 18, color: Colors.white),
                                  title: Text(v['title'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  trailing: IconButton(
                                    icon: const Icon(LucideIcons.download, color: AppColors.accentYellow, size: 16),
                                    onPressed: () => _startDownload(v['id'].toString(), v['title'], chapter['title']),
                                  ),
                                  onTap: () => _playVideo(v),
                                )),

                                // PDFs
                                ...pdfs.map((p) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(LucideIcons.fileText, size: 18, color: AppColors.textSecondary),
                                  title: Text(p['title'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                  trailing: const Icon(LucideIcons.eye, color: AppColors.accentYellow, size: 16),
                                  onTap: () {
                                     Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfId: p['id'].toString(), title: p['title'])));
                                  },
                                )),
                              ],
                            ],
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: exams.length,
                      itemBuilder: (context, index) {
                        final exam = exams[index];
                        final bool isCompleted = exam['isCompleted'] ?? false;
                        
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ExamViewScreen(
                                examId: exam['id'].toString(),
                                examTitle: exam['title'],
                                isCompleted: isCompleted,
                              )),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isCompleted ? AppColors.success.withOpacity(0.5) : Colors.white.withOpacity(0.05)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48, height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundPrimary,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  ),
                                  child: Icon(LucideIcons.fileCheck, color: isCompleted ? AppColors.success : AppColors.accentOrange, size: 20),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        exam['title'].toString().toUpperCase(),
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "${exam['duration_minutes']} MINS • ${isCompleted ? 'SOLVED' : 'PENDING'}",
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isCompleted ? AppColors.success : AppColors.textSecondary.withOpacity(0.7), letterSpacing: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(isCompleted ? LucideIcons.checkCircle : LucideIcons.chevronRight, size: 20, color: isCompleted ? AppColors.success : AppColors.textSecondary),
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

  Widget _buildTab(String title, String key) {
    final isActive = _activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = key),
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
}
