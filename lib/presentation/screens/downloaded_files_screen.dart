import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'downloaded_subjects_screen.dart';

// ✅ تعريف البيانات خارج الكلاس لضمان الوصول إليها
class DownloadItem {
  final String id;
  final String title;
  final String type;
  final String size;
  final String course;
  final String subject;
  final String chapter;

  DownloadItem({
    required this.id, required this.title, required this.type,
    required this.size, required this.course, required this.subject, required this.chapter
  });
}

// ✅ بيانات وهمية ثابتة
final List<DownloadItem> allDownloads = [
    DownloadItem(id: 'd1', title: 'Dynamic Coloring Video', type: 'video', size: '45MB', course: 'Modern UI Design with Material 3', subject: 'Design Foundations', chapter: 'Dynamic Coloring'),
    DownloadItem(id: 'd2', title: 'M3 Guidelines', type: 'pdf', size: '2MB', course: 'Modern UI Design with Material 3', subject: 'Design Foundations', chapter: 'Dynamic Coloring'),
    DownloadItem(id: 'd3', title: 'Responsive Grids', type: 'video', size: '62MB', course: 'Modern UI Design with Material 3', subject: 'Layout Systems', chapter: 'Grid vs Flex'),
];

class DownloadedFilesScreen extends StatefulWidget {
  const DownloadedFilesScreen({super.key});

  @override
  State<DownloadedFilesScreen> createState() => _DownloadedFilesScreenState();
}

class _DownloadedFilesScreenState extends State<DownloadedFilesScreen> {
  // ... (نفس كود المؤقت السابق)

  @override
  Widget build(BuildContext context) {
    // Grouping Logic
    final Map<String, int> groupedCourses = {};
    for (var item in allDownloads) {
      groupedCourses[item.course] = (groupedCourses[item.course] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header (نفس السابق)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: const Icon(LucideIcons.downloadCloud, color: AppColors.accentYellow, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("DOWNLOADS", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          SizedBox(height: 4),
                          Text("LOCAL COURSES", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    // Active Downloads (اختياري)
                    
                    // List
                    if (groupedCourses.isEmpty)
                      const Center(child: Text("NO DOWNLOADS", style: TextStyle(color: Colors.white)))
                    else
                      ...groupedCourses.entries.map((entry) => GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DownloadedSubjectsScreen(courseTitle: entry.key),
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundPrimary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(LucideIcons.book, color: AppColors.accentOrange, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.key.toUpperCase(),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "${entry.value} FILES",
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary.withOpacity(0.7)),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withOpacity(0.6), size: 20),
                            ],
                          ),
                        ),
                      )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
