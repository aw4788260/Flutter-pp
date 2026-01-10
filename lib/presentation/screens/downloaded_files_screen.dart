import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/local_proxy.dart';
import 'downloaded_subjects_screen.dart'; // تأكد من وجود هذا الملف أو استبدله بمسارك الصحيح

class DownloadedFilesScreen extends StatefulWidget {
  const DownloadedFilesScreen({super.key});

  @override
  State<DownloadedFilesScreen> createState() => _DownloadedFilesScreenState();
}

class _DownloadedFilesScreenState extends State<DownloadedFilesScreen> {
  final LocalProxyService _proxy = LocalProxyService();
  
  // قائمة التحميلات النشطة (مستقبلاً يمكن ربطها بـ DownloadManager)
  List<Map<String, dynamic>> activeDownloads = []; 

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // التأكد من فتح الصندوق قبل استخدامه
    if (!Hive.isBoxOpen('downloads_box')) {
      await Hive.openBox('downloads_box');
    }
    
    // تشغيل السيرفر المحلي لتشغيل الفيديوهات المشفرة
    await _proxy.start();
    
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _proxy.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header Section
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
                              fontSize: 24,
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
                  
                  // Active Downloads Badge (Optional)
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

            // Content List with Auto-Refresh Logic
            Expanded(
              child: ValueListenableBuilder(
                // الاستماع للتغييرات في صندوق التحميلات
                valueListenable: Hive.box('downloads_box').listenable(),
                builder: (context, Box box, _) {
                  // إعادة تجميع الكورسات عند كل تحديث
                  final Map<String, int> groupedCourses = {};
                  
                  for (var key in box.keys) {
                    final item = box.get(key);
                    // تجميع حسب اسم الكورس
                    final courseName = item['course'] ?? 'Unknown Course';
                    groupedCourses[courseName] = (groupedCourses[courseName] ?? 0) + 1;
                  }

                  // حالة القائمة الفارغة
                  if (groupedCourses.isEmpty && activeDownloads.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Text(
                          "NO STORED FILES",
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.white24, 
                            letterSpacing: 2.0
                          ),
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // قسم التحميلات النشطة (مخصص للعرض حالياً)
                        if (activeDownloads.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              "ACTIVE DOWNLOADS",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                            ),
                          ),
                          // هنا يمكنك إضافة كود عرض عناصر التحميل الجاري...
                        ],

                        // قسم الكورسات المحملة
                        if (groupedCourses.isNotEmpty) ...[
                          if (activeDownloads.isNotEmpty) const SizedBox(height: 24), // مسافة فاصلة إذا وجد تحميل نشط
                          
                          ...groupedCourses.entries.map((entry) => GestureDetector(
                            onTap: () {
                              // الانتقال لشاشة المواد الخاصة بالكورس
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DownloadedSubjectsScreen(courseTitle: entry.key),
                                ),
                              );
                            },
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
                                  // أيقونة الكتاب
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundPrimary,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                    ),
                                    child: const Icon(LucideIcons.book, color: AppColors.accentOrange, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  
                                  // تفاصيل الكورس
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
                                            letterSpacing: -0.5
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
                                            letterSpacing: 1.5
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // سهم الانتقال
                                  Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withOpacity(0.6), size: 20),
                                ],
                              ),
                            ),
                          )),
                        ],
                      ],
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
