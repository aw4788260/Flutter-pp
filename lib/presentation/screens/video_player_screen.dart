import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';

class VideoPlayerScreen extends StatelessWidget {
  final String lessonTitle;

  const VideoPlayerScreen({super.key, required this.lessonTitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // المشغل دائماً أسود
      body: SafeArea(
        child: Column(
          children: [
            // 1. منطقة الفيديو (Simulated)
            Expanded(
              flex: 3,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(color: Colors.black),
                  const Icon(LucideIcons.playCircle, size: 64, color: AppColors.accentYellow),
                  // زر الرجوع العائم
                  Positioned(
                    top: 16,
                    left: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // 2. تفاصيل أسفل الفيديو
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                color: AppColors.backgroundPrimary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lessonTitle,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Section 1: Introduction",
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white10),
                    // يمكن إضافة تبويبات (Notes, Q&A) هنا
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
