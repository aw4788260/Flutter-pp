import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Lesson lesson;

  const VideoPlayerScreen({super.key, required this.lesson});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // Normally use video_player package, here we simulate UI
  bool _showControls = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video Placeholder (Simulated)
            Container(width: double.infinity, height: double.infinity, color: Colors.black),
            
            // Simulated Video Content
            const Text("VIDEO PLAYING...", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 2.0)),

            // Controls Overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                color: Colors.black.withOpacity(0.4),
                padding: const EdgeInsets.all(24),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 24),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: const [
                              Text(
                                "Watching Now",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                "HD STREAMING",
                                style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5),
                              ),
                            ],
                          )
                        ],
                      ),

                      // Center Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.skipBack, color: Colors.white70, size: 36),
                          const SizedBox(width: 48),
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow,
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(color: AppColors.accentYellow, blurRadius: 25)],
                            ),
                            child: const Icon(LucideIcons.play, color: Colors.white, size: 40),
                          ),
                          const SizedBox(width: 48),
                          const Icon(LucideIcons.skipForward, color: Colors.white70, size: 36),
                        ],
                      ),

                      // Bottom Bar
                      Column(
                        children: [
                          // Progress Bar
                          Container(
                            height: 4,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: MediaQuery.of(context).size.width * 0.45,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.accentYellow,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: const [BoxShadow(color: AppColors.accentYellow, blurRadius: 8)],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Settings
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "HD 1080P",
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                              ),
                              Row(
                                children: const [
                                  Icon(LucideIcons.settings, color: Colors.white, size: 20),
                                  SizedBox(width: 24),
                                  Icon(LucideIcons.maximize, color: Colors.white, size: 20),
                                ],
                              ),
                            ],
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
    );
  }
}
