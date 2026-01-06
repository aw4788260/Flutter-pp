import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';
import 'video_player_screen.dart';

class VideoPreviewScreen extends StatefulWidget {
  final Lesson lesson;

  const VideoPreviewScreen({super.key, required this.lesson});

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  bool isDownloading = false;
  int progress = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startDownload() {
    if (isDownloading) return;
    setState(() {
      isDownloading = true;
      progress = 0;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      setState(() {
        if (progress >= 100) {
          timer.cancel();
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) setState(() => isDownloading = false);
          });
        } else {
          progress += 10;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                ),
              ),
              
              Text(
                widget.lesson.title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Prepare for your session. Choose an action to begin.",
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 48),

              // Watch Online Button
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  "VIDEO CONTENT",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(lesson: widget.lesson))),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentYellow.withOpacity(0.2),
                        blurRadius: 15,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.play, color: AppColors.backgroundPrimary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "WATCH ONLINE",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.backgroundPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "STREAM",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.backgroundPrimary.withOpacity(0.7),
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Download Button
              Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    if (isDownloading)
                      Positioned(
                        bottom: 0, left: 0,
                        height: 4,
                        width: MediaQuery.of(context).size.width * (progress / 100),
                        child: Container(color: AppColors.accentYellow),
                      ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _startDownload,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundPrimary,
                                  shape: BoxShape.circle,
                                  // ✅ Fix: Removed inset: true
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: isDownloading 
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentYellow))
                                  : const Icon(LucideIcons.download, color: AppColors.accentYellow, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "DOWNLOAD OFFLINE",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isDownloading ? "DOWNLOADING $progress%..." : "SAVE TO LOCAL DEVICE",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textSecondary,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // PDF Resource
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  "LESSON PDF MATERIALS",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundPrimary,
                            borderRadius: BorderRadius.circular(12),
                            // ✅ Fix: Removed inset: true
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                          ),
                          child: const Icon(LucideIcons.fileText, color: AppColors.accentYellow, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "SESSION DOCUMENTS",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "RESOURCES FOR THIS VIDEO",
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary.withOpacity(0.7),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: const Icon(LucideIcons.eye, color: AppColors.accentYellow, size: 18),
                    ),
                  ],
                ),
              ),

              const Spacer(),
              Center(
                child: Text(
                  "ADVANCED LEARNING CONSOLE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary.withOpacity(0.4),
                    letterSpacing: 3.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
