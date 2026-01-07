import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';
import 'downloaded_files_screen.dart'; // For allDownloads
import 'video_player_screen.dart';

class DownloadedChapterContentsScreen extends StatefulWidget {
  final String courseTitle;
  final String subjectTitle;
  final String chapterTitle;

  const DownloadedChapterContentsScreen({
    super.key,
    required this.courseTitle,
    required this.subjectTitle,
    required this.chapterTitle,
  });

  @override
  State<DownloadedChapterContentsScreen> createState() => _DownloadedChapterContentsScreenState();
}

class _DownloadedChapterContentsScreenState extends State<DownloadedChapterContentsScreen> {
  String activeTab = 'videos'; // 'videos' | 'pdfs'

  @override
  Widget build(BuildContext context) {
    final chapterFiles = allDownloads.where((d) => 
      d.course == widget.courseTitle && 
      d.subject == widget.subjectTitle && 
      d.chapter == widget.chapterTitle
    ).toList();

    final videos = chapterFiles.where((f) => f.type == 'video').toList();
    final pdfs = chapterFiles.where((f) => f.type == 'pdf').toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header (Sticky effect)
            Container(
              color: AppColors.backgroundPrimary.withOpacity(0.95),
              child: Column(
                children: [
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
                                widget.chapterTitle.toUpperCase(),
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
                                "DOWNLOADED FILES",
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

                  // Tab Switcher
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Row(
                        children: [
                          _buildTab("Videos (${videos.length})", 'videos'),
                          _buildTab("PDFs (${pdfs.length})", 'pdfs'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: activeTab == 'videos'
                  ? _buildFileList(videos, LucideIcons.play)
                  : _buildFileList(pdfs, LucideIcons.fileText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title, String key) {
    final isActive = activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => activeTab = key),
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

  Widget _buildFileList(List<DownloadItem> files, IconData icon) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              activeTab == 'videos' ? LucideIcons.monitorPlay : LucideIcons.fileSearch,
              size: 48, 
              color: AppColors.textSecondary.withOpacity(0.3)
            ),
            const SizedBox(height: 16),
            Text(
              "NO ${activeTab.toUpperCase()} DOWNLOADED",
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

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (item.type == 'video') {
                      // Navigate to player with dummy lesson data
                      final lesson = Lesson(id: item.id, title: item.title, type: LessonType.video);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(lesson: lesson)));
                    } else {
                      // Mock PDF open
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Opening PDF: ${item.title}")));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundPrimary,
                            borderRadius: BorderRadius.circular(8),
                            // ✅ تم التصحيح: إزالة inset: true
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                          ),
                          child: Icon(icon, color: activeTab == 'videos' ? AppColors.accentOrange : AppColors.accentYellow, size: 14),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.size,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 32, color: Colors.white.withOpacity(0.05)),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 14, color: AppColors.accentOrange),
                onPressed: () {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Removed ${item.title}")));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
