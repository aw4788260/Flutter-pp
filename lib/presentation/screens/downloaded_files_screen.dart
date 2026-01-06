import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'downloaded_subjects_screen.dart';

// --- Mock Data for Downloads (Matching React Data) ---
class DownloadItem {
  final String id;
  final String title;
  final String type; // 'video' | 'pdf'
  final String size;
  final String course;
  final String subject;
  final String chapter;

  DownloadItem({
    required this.id, required this.title, required this.type,
    required this.size, required this.course, required this.subject, required this.chapter
  });
}

final List<DownloadItem> allDownloads = [
    DownloadItem(id: 'd1', title: 'Dynamic Coloring Video', type: 'video', size: '45MB', course: 'Modern UI Design with Material 3', subject: 'Design Foundations', chapter: 'Dynamic Coloring'),
    DownloadItem(id: 'd2', title: 'M3 Guidelines', type: 'pdf', size: '2MB', course: 'Modern UI Design with Material 3', subject: 'Design Foundations', chapter: 'Dynamic Coloring'),
    DownloadItem(id: 'd3', title: 'Responsive Grids', type: 'video', size: '62MB', course: 'Modern UI Design with Material 3', subject: 'Layout Systems', chapter: 'Grid vs Flex'),
    DownloadItem(id: 'd4', title: 'React Core Internals', type: 'video', size: '115MB', course: 'Advanced React Architecture', subject: 'React Core Internals', chapter: 'Introduction'),
    DownloadItem(id: 'd5', title: 'React Hooks Deep Dive', type: 'pdf', size: '5MB', course: 'Advanced React Architecture', subject: 'React Core Internals', chapter: 'Hooks'),
];

// --- Screen ---
class DownloadedFilesScreen extends StatefulWidget {
  const DownloadedFilesScreen({super.key});

  @override
  State<DownloadedFilesScreen> createState() => _DownloadedFilesScreenState();
}

class _DownloadedFilesScreenState extends State<DownloadedFilesScreen> {
  // Active Downloads Simulation
  List<Map<String, dynamic>> activeDownloads = [
    {'id': 'ad1', 'title': 'Extraction Logic', 'progress': 45}
  ];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Simulate Progress
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          activeDownloads = activeDownloads.map((dl) {
            final newProgress = (dl['progress'] as int) + 5;
            return {...dl, 'progress': newProgress > 100 ? 100 : newProgress};
          }).toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancelDownload(String id) {
    setState(() {
      activeDownloads.removeWhere((element) => element['id'] == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Group downloads by Course
    final Map<String, int> groupedCourses = {};
    for (var item in allDownloads) {
      groupedCourses[item.course] = (groupedCourses[item.course] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                          Text(
                            "DOWNLOADS",
                            style: TextStyle(
                              fontSize: 24, // text-3xl
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              height: 1.0,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "LOCAL COURSES",
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (activeDownloads.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                      ),
                      child: const Text(
                        "QUEUE",
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentYellow,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Active Downloads Section
                    if (activeDownloads.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          "ACTIVE DOWNLOADS",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                      ...activeDownloads.map((dl) => Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(20), // rounded-m3-xl
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(LucideIcons.loader2, size: 16, color: AppColors.accentYellow), // Should animate rotate
                                    const SizedBox(width: 12),
                                    Text(
                                      (dl['title'] as String).toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text(
                                      "${dl['progress']}%",
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.accentYellow,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => _cancelDownload(dl['id']),
                                      child: const Icon(LucideIcons.x, size: 16, color: AppColors.accentOrange),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Progress Bar
                            Container(
                              height: 6,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppColors.backgroundPrimary,
                                borderRadius: BorderRadius.circular(3),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, inset: true)],
                              ),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: (dl['progress'] as int) / 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.accentYellow,
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: const [BoxShadow(color: AppColors.accentYellow, blurRadius: 8)],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],

                    // Downloaded Courses List
                    if (groupedCourses.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Text(
                            "NO STORED FILES",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white24,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                      )
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
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, inset: true)],
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
                                      "${entry.value} FILES DOWNLOADED",
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
