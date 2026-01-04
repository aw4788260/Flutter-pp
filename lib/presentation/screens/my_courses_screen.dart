import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class MyCoursesScreen extends StatelessWidget {
  const MyCoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text("My Courses", style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
      ),
      body: const Center(
        child: Text(
          "No courses yet.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
