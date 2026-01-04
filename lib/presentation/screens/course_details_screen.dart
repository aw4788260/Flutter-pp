import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/chapter_model.dart'; // استيراد البيانات
import '../widgets/chapter_accordion.dart'; // استيراد الودجت

class CourseDetailsScreen extends StatefulWidget {
  const CourseDetailsScreen({super.key});

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        children: [
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
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
                        // صورة الكورس
                        Container(color: AppColors.backgroundSecondary),
                        const Center(child: Icon(LucideIcons.image, size: 64, color: Colors.white24)),
                        // تدرج لوني
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
                
                // شريط التبويبات (Sticky TabBar)
                SliverPersistentHeader(
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: AppColors.accentYellow,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.accentYellow,
                      dividerColor: Colors.white.withOpacity(0.05),
                      tabs: const [
                        Tab(text: "Overview"),
                        Tab(text: "Curriculum"),
                      ],
                    ),
                  ),
                  pinned: true,
                ),
              ];
            },
            // محتوى التبويبات
            body: TabBarView(
              controller: _tabController,
              children: [
                // 1. Overview Tab
                _buildOverviewTab(),
                
                // 2. Curriculum Tab (المحتوى)
                _buildCurriculumTab(),
              ],
            ),
          ),

          // زر الاشتراك العائم (Bottom Bar)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
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
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  // محتوى تبويب "نظرة عامة"
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), // مسافة للزر السفلي
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & Instructor
          const Text(
            "Advanced Mechanics & Motion",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
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
            "This course covers the complete Physics curriculum for High School students. It includes detailed video lectures, PDF notes, and interactive exams to ensure you get the full mark.",
            style: TextStyle(color: AppColors.textPrimary, height: 1.6),
          ),
        ],
      ),
    );
  }

  // محتوى تبويب "المنهج"
  Widget _buildCurriculumTab() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: dummyChapters.length,
      itemBuilder: (context, index) {
        return ChapterAccordion(chapter: dummyChapters[index], index: index);
      },
    );
  }
}

// كلاس مساعد لتثبيت التبويبات (Sliver Header Delegate)
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.backgroundPrimary, // لون خلفية الشريط عند التمرير
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
