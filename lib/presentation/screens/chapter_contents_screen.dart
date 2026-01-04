import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/chapter_model.dart';
import 'video_player_screen.dart'; // الصفحة التالية

class ChapterContentsScreen extends StatelessWidget {
  final Chapter chapter;

  const ChapterContentsScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        title: Text(chapter.title, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: chapter.lessons.length,
        itemBuilder: (context, index) {
          final lesson = chapter.lessons[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  lesson.isFree ? LucideIcons.play : LucideIcons.lock,
                  color: lesson.isFree ? AppColors.accentYellow : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              title: Text(
                lesson.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                "Duration: ${lesson.duration}",
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textSecondary),
              onTap: () {
                if (lesson.isFree) {
                  // ✅ الانتقال لمشغل الفيديو
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoPlayerScreen(lessonTitle: lesson.title),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("This lesson is locked.")),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}
