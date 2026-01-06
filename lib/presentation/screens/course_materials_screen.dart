import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';
import '../../data/mock_data.dart';
import 'subject_materials_screen.dart';
import 'my_courses_screen.dart';

class CourseMaterialsScreen extends StatelessWidget {
  final CourseModel? course; // Optional for safety

  const CourseMaterialsScreen({super.key, this.course});

  @override
  Widget build(BuildContext context) {
    // Fallback if accessed without course (e.g. direct nav)
    final safeCourse = course ?? mockCourses[0]; 
    final teacher = mockTeachers.firstWhere((t) => t.id == safeCourse.teacherId);

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MyCoursesScreen())),
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
                          safeCourse.title.toUpperCase(),
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
                          "CHOOSE SUBJECT",
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

            // Content
            Expanded(
              child: safeCourse.subjects.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.layers, size: 40, color: AppColors.textSecondary.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(
                        "NO SUBJECTS",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary.withOpacity(0.5),
                          letterSpacing: 2.0,
                        ),
                      )
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: safeCourse.subjects.length,
                  itemBuilder: (context, index) {
                    final subject = safeCourse.subjects[index];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SubjectMaterialsScreen(course: safeCourse, subject: subject)),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Icon
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accentOrange,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: AppColors.accentOrange, blurRadius: 4)],
                                  ),
                                ),
                                const Icon(LucideIcons.playCircle, size: 20, color: AppColors.accentOrange),
                              ],
                            ),

                            // Title
                            Text(
                              subject.title.toUpperCase(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                height: 1.1,
                                letterSpacing: -0.5,
                              ),
                            ),

                            // Footer
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        teacher.name.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textSecondary.withOpacity(0.7),
                                          letterSpacing: 1.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        height: 2, width: 24,
                                        decoration: BoxDecoration(
                                          color: AppColors.accentOrange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(1),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 24, height: 24,
                                  decoration: const BoxDecoration(
                                    color: AppColors.backgroundPrimary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.chevronRight, size: 14, color: AppColors.accentOrange),
                                ),
                              ],
                            ),
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
}
