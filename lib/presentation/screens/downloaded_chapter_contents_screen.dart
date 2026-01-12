import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/local_proxy.dart';
import 'video_player_screen.dart';

class DownloadedChapterContentsScreen extends StatefulWidget {
  final String courseTitle;
  final String subjectTitle;
  final String chapterTitle;

  const DownloadedChapterContentsScreen({
    super.key,
    required this.courseTitle,
    required this.subjectTitle,
    required this.chapterTitle,
  });

  @override
  State<DownloadedChapterContentsScreen> createState() => _DownloadedChapterContentsScreenState();
}

class _DownloadedChapterContentsScreenState extends State<DownloadedChapterContentsScreen> {
  String activeTab = 'videos';

  // --- تشغيل الفيديو أوفلاين ---
  void _playOfflineVideo(Map<dynamic, dynamic> item) {
    final proxyUrl = "http://127.0.0.1:8080/video?path=${Uri.encodeComponent(item['path'])}";
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streams: {"Offline": proxyUrl}, 
          title: item['title'] ?? "Offline Video",
        ),
      ),
    );
  }

  // --- حذف الملف ---
  Future<void> _deleteFile(String key) async {
    var box = await Hive.openBox('downloads_box');
    await box.delete(key);
    setState(() {});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("File removed"), backgroundColor: AppColors.accentOrange));
  }

  @override
  Widget build(BuildContext context) {
    // 1. جلب البيانات من Hive
    var box = Hive.box('downloads_box');
    
    // إعداد القوائم مع حفظ المفتاح (key) داخل العنصر لسهولة الحذف
    List<Map<String, dynamic>> videoItems = [];
    List<Map<String, dynamic>> pdfItems = [];

    for (var key in box.keys) {
      final item = box.get(key);
      // تصفية العناصر الخاصة بالشابتر الحالي
      if (item['course'] == widget.courseTitle && 
          item['subject'] == widget.subjectTitle &&
          item['chapter'] == widget.chapterTitle) {
        
        // تحويل العنصر إلى Map قابل للتعديل وإضافة المفتاح
        final itemMap = Map<String, dynamic>.from(item);
        itemMap['key'] = key;

        if (item['type'] == 'pdf') {
          pdfItems.add(itemMap);
        } else {
          videoItems.add(itemMap);
        }
      }
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24.0),
              color: AppColors.backgroundPrimary.withOpacity(0.95),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.chapterTitle.toUpperCase(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // ✅ عرض المسار الكامل في الهيدر (كورس > مادة)
                        Text(
                          "${widget.courseTitle} > ${widget.subjectTitle}",
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withOpacity(0.7)),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab Switcher
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    _buildTab("Videos (${videoItems.length})", 'videos'),
                    _buildTab("PDFs (${pdfItems.length})", 'pdfs'),
                  ],
                ),
              ),
            ),

            // List
            Expanded(
              child: activeTab == 'videos'
                  ? _buildFileList(videoItems, LucideIcons.play)
                  : _buildFileList(pdfItems, LucideIcons.fileText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title, String key) {
    final isActive = activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => activeTab = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.backgroundPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: isActive ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
          ),
          child: Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isActive ? AppColors.accentYellow : AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(List<Map<String, dynamic>> items, IconData icon) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              activeTab == 'videos' ? LucideIcons.monitorPlay : LucideIcons.fileSearch,
              size: 48, 
              color: AppColors.textSecondary.withOpacity(0.3)
            ),
            const SizedBox(height: 16),
            Text(
              "NO ${activeTab.toUpperCase()} DOWNLOADED",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final key = item['key']; // المفتاح للحذف
        
        // استخراج البيانات
        final sizeBytes = item['size'] ?? 0;
        final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
        final quality = item['quality'] ?? "SD";
        final duration = item['duration'] ?? "--:--";

        // ✅ استخدام GestureDetector على كامل البطاقة
        return GestureDetector(
          onTap: () {
             if (activeTab == 'videos') {
               _playOfflineVideo(item);
             } else {
               // فتح PDF
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Opening PDF: ${item['title']}")));
             }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12), // تقليل المسافة بين البطاقات
            padding: const EdgeInsets.all(12), // تقليل الحشو الداخلي لجعل البطاقة أصغر
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(12), // تقليل نصف قطر الحواف قليلاً
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ❌ تم إزالة الهيكل الشجري من داخل البطاقة بناءً على طلبك

                // 2. العنوان والأيقونة وزر الحذف
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8), // أيقونة أصغر
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: activeTab == 'videos' ? AppColors.accentOrange : AppColors.accentYellow, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item['title'].toString().toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13, // خط أصغر قليلاً للعنوان
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.2
                        ),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // زر الحذف (مفصول عن ضغطة البطاقة)
                    GestureDetector(
                      onTap: () => _deleteFile(key.toString()),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(LucideIcons.trash2, size: 16, color: AppColors.error),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8), // تقليل المسافة
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 8), // تقليل المسافة

                // 3. شريط المعلومات (جودة | مدة | حجم)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetaTag(LucideIcons.monitor, quality),
                    if(activeTab == 'videos') _buildMetaTag(LucideIcons.clock, duration),
                    _buildMetaTag(LucideIcons.hardDrive, "$sizeMB MB"),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetaTag(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 10, color: AppColors.accentYellow), // أيقونة أصغر
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.bold), // خط أصغر
        ),
      ],
    );
  }
}
