import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';
import 'video_player_screen.dart'; // ✅ تأكد من الاستيراد

class ChapterContentsScreen extends StatefulWidget {
  final Chapter chapter;

  const ChapterContentsScreen({super.key, required this.chapter});

  @override
  State<ChapterContentsScreen> createState() => _ChapterContentsScreenState();
}

class _ChapterContentsScreenState extends State<ChapterContentsScreen> {
  String activeTab = 'videos';

  @override
  Widget build(BuildContext context) {
    final videos = widget.chapter.lessons.where((l) => l.type == LessonType.video).toList();
    final pdfs = widget.chapter.lessons.where((l) => l.type == LessonType.file).toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: AppColors.backgroundPrimary.withOpacity(0.95),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context), // ✅ استخدام pop للرجوع
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
                                widget.chapter.title.toUpperCase(),
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
                                "MATERIALS EXPLORER",
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
                          _buildTab("Videos", 'videos'),
                          _buildTab("PDFs", 'pdfs'),
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
                  ? _buildVideosList(videos)
                  : _buildPdfsList(pdfs),
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

  Widget _buildVideosList(List<Lesson> videos) {
    if (videos.isEmpty) {
      return _buildEmptyState(LucideIcons.monitorPlay, "No video lessons");
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Top Section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                      ),
                      child: const Icon(LucideIcons.play, color: AppColors.accentOrange, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title.toUpperCase(),
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
                          Text(
                            "SESSION",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary.withOpacity(0.7),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      "Watch Now", 
                      AppColors.accentYellow, 
                      // ✅ فتح الفيديو مباشرة
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(lesson: video))),
                    ),
                  ),
                  Container(width: 1, height: 48, color: Colors.white10),
                  Expanded(
                    child: _buildActionButton(
                      "Download", 
                      AppColors.textSecondary, 
                      () { /* Mock Download */ },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPdfsList(List<Lesson> pdfs) {
    if (pdfs.isEmpty) {
      return _buildEmptyState(LucideIcons.fileSearch, "No PDF resources");
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: pdfs.length,
      itemBuilder: (context, index) {
        final pdf = pdfs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                      ),
                      child: const Icon(LucideIcons.fileText, color: AppColors.accentYellow, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pdf.title.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "STUDY MATERIAL",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton("View PDF", AppColors.accentYellow, () {}),
                  ),
                  Container(width: 1, height: 48, color: Colors.white10),
                  Expanded(
                    child: _buildActionButton("Download", AppColors.textSecondary, () {}),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: color,
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
