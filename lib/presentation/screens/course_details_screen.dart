import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';
import '../../data/mock_data.dart';
import 'checkout_screen.dart';

class CourseDetailsScreen extends StatefulWidget {
  final CourseModel? course;

  const CourseDetailsScreen({super.key, this.course});

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> {
  late CourseModel course;
  List<String> selectedSubjectIds = [];
  bool isFullCourse = false;

  @override
  void initState() {
    super.initState();
    course = widget.course ?? mockCourses[0]; 
  }

  void _toggleSubject(String id) {
    setState(() {
      isFullCourse = false;
      if (selectedSubjectIds.contains(id)) {
        selectedSubjectIds.remove(id);
      } else {
        selectedSubjectIds.add(id);
      }
    });
  }

  void _toggleFullCourse() {
    setState(() {
      isFullCourse = !isFullCourse;
      selectedSubjectIds.clear();
    });
  }

  void _handleEnroll() {
    final double finalPrice = isFullCourse 
        ? course.fullPrice 
        : course.subjects
            .where((s) => selectedSubjectIds.contains(s.id))
            .fold(0, (sum, s) => sum + s.price);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(amount: finalPrice),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double currentPrice = isFullCourse 
        ? course.fullPrice 
        : course.subjects
            .where((s) => selectedSubjectIds.contains(s.id))
            .fold(0, (sum, s) => sum + s.price);

    final bool hasSelection = isFullCourse || selectedSubjectIds.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back Button
                      GestureDetector(
                        onTap: () => Navigator.pop(context), // ✅ استخدام pop للرجوع للبار السفلي
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 32),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                        ),
                      ),
                      
                      // ... (بقية تفاصيل الكورس كما هي)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Text(
                              course.category.toUpperCase(),
                              style: const TextStyle(color: AppColors.accentYellow, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "ID: #${course.id.toUpperCase()}",
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        course.title.toUpperCase(),
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1.0, height: 1.1),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        course.description,
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        ),
                        child: Row(
                          children: const [
                            Icon(LucideIcons.shieldCheck, color: AppColors.accentYellow, size: 20),
                            SizedBox(width: 12),
                            Text("ACCREDITED COURSE ACCESS", style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text("PACKAGE BUILDER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.textSecondary, letterSpacing: 1.5)),
                          Icon(LucideIcons.box, color: AppColors.accentYellow, size: 20),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 32),

                      // Full Course Option
                      GestureDetector(
                        onTap: _toggleFullCourse,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isFullCourse ? AppColors.accentYellow : Colors.white.withOpacity(0.05), width: 1),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                          ),
                          // ✅ محاذاة السعر والنص
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(color: AppColors.backgroundPrimary, borderRadius: BorderRadius.circular(12)),
                                      child: const Icon(LucideIcons.shoppingBag, color: AppColors.textSecondary, size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("FULL COURSE PASS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                          const SizedBox(height: 4),
                                          Text("Access all subjects & exams", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isFullCourse ? AppColors.accentYellow : AppColors.textSecondary.withOpacity(0.7))),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text("\$${course.fullPrice}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                                  if (isFullCourse) ...[
                                    const SizedBox(height: 8),
                                    const Icon(LucideIcons.checkCircle2, color: AppColors.accentYellow, size: 18),
                                  ]
                                ],
                              )
                            ],
                          ),
                        ),
                      ),

                      // Subjects List
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Row(
                          children: [
                            const Expanded(child: Divider(color: Colors.white10)),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("INDIVIDUAL SELECTION", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textSecondary, letterSpacing: 1.5))),
                            const Expanded(child: Divider(color: Colors.white10)),
                          ],
                        ),
                      ),
                      ...course.subjects.map((subject) {
                        final isSelected = selectedSubjectIds.contains(subject.id);
                        return GestureDetector(
                          onTap: () => _toggleSubject(subject.id),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? AppColors.accentYellow.withOpacity(0.4) : Colors.white.withOpacity(0.05)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 32, height: 32,
                                      decoration: BoxDecoration(color: AppColors.backgroundPrimary, borderRadius: BorderRadius.circular(8), boxShadow: [if (isSelected) BoxShadow(color: AppColors.accentYellow.withOpacity(0.2), blurRadius: 4)]),
                                      child: Icon(LucideIcons.bookOpen, size: 14, color: isSelected ? AppColors.accentYellow : AppColors.textSecondary.withOpacity(0.6)),
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(subject.title.toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary)),
                                        const SizedBox(height: 2),
                                        Text("${subject.chapters.length} Modules", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary.withOpacity(0.6), letterSpacing: 1.5)),
                                      ],
                                    ),
                                  ],
                                ),
                                Text("\$${subject.price}", style: TextStyle(fontWeight: FontWeight.w900, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary.withOpacity(0.7))),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (hasSelection)
            Positioned(
              bottom: 40, left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.accentYellow.withOpacity(0.1)),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 10))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(LucideIcons.shoppingBag, color: AppColors.accentYellow, size: 24),
                            Positioned(
                              top: -6, right: -6,
                              child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(color: AppColors.accentOrange, shape: BoxShape.circle, border: Border.all(color: AppColors.backgroundPrimary, width: 2)),
                                child: Center(child: Text("${isFullCourse ? 1 : selectedSubjectIds.length}", style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("SUBTOTAL", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.textSecondary, letterSpacing: 1.5)),
                            Text("\$$currentPrice", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.0)),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _handleEnroll,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: Row(
                        children: const [
                          Text("CONFIRM", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                          SizedBox(width: 8),
                          Icon(LucideIcons.chevronRight, size: 18),
                        ],
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
