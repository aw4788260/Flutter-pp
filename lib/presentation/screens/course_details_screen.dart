import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'course_materials_screen.dart'; // الانتقال للصفحة التالية في القائمة

class CourseDetailsScreen extends StatelessWidget {
  const CourseDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 250.0,
                pinned: true,
                backgroundColor: AppColors.backgroundPrimary,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: AppColors.backgroundSecondary),
                      const Center(child: Icon(LucideIcons.image, size: 64, color: Colors.white24)),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppColors.backgroundPrimary],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                        ),
                        child: const Text("PHYSICS", style: TextStyle(color: AppColors.accentYellow, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 16),
                      
                      // Title
                      const Text(
                        "Advanced Mechanics & Motion",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 16),

                      // Instructor
                      Row(
                        children: [
                          const CircleAvatar(radius: 20, backgroundColor: AppColors.backgroundSecondary, child: Icon(LucideIcons.user, size: 20)),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text("Mr. Ahmed Hassan", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                              Text("Senior Physics Teacher", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 24),

                      // Description
                      const Text("ABOUT THIS COURSE", style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      const Text(
                        "This course covers the complete Physics curriculum. Include Newton's laws, Energy, and more. Perfect for final revision.",
                        style: TextStyle(color: AppColors.textPrimary, height: 1.6),
                      ),
                      const SizedBox(height: 100), // مسافة للزر
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Footer Action Button
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("Total Price", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      Text("1,200 EGP", style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // هنا ننتقل لصفحة المواد (وكأن الطالب اشترك)
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CourseMaterialsScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("ENROLL NOW", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
