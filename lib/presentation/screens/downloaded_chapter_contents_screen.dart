import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/local_proxy.dart'; // لتشغيل الفيديو
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
  String activeTab = 'videos'; // 'videos' | 'pdfs'

  // --- تشغيل الفيديو أوفلاين ---
  void _playOfflineVideo(Map<dynamic, dynamic> item) {
    final proxyUrl = "http://127.0.0.1:8080/video?path=${item['path']}";
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
    // يمكنك إضافة حذف الملف الفعلي من الجهاز هنا باستخدام dart:io
    setState(() {}); // تحديث الواجهة
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("File removed"), backgroundColor: AppColors.accentOrange));
  }

  @override
  Widget build(BuildContext context) {
    // 1. جلب وتصفية البيانات من Hive
    var box = Hive.box('downloads_box');
    List<Map<dynamic, dynamic>> chapterFiles = [];
    List<dynamic> keys = []; // لحفظ المفاتيح للحذف

    for (var key in box.keys) {
      final item = box.get(key);
      if (item['course'] == widget.courseTitle && 
          item['subject'] == widget.subjectTitle &&
          item['chapter'] == widget.chapterTitle) {
        chapterFiles.add(item);
        keys.add(key);
      }
    }

    // 2. تصنيف الملفات (حالياً نعتبر الكل فيديو لأننا لم نضف نوع الملف عند التحميل بعد)
    // إذا قمت بتحديث DownloadManager لحفظ النوع 'type': 'video'/'pdf'، يمكنك استخدام الفلتر أدناه
    // حالياً سنفترض أن الكل فيديو حتى يتم دعم PDF
    final videos = chapterFiles; 
    final pdfs = <Map<dynamic, dynamic>>[]; 

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header (Sticky effect)
            Container(
              color: AppColors.backgroundPrimary.withOpacity(0.95),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
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
                                widget.chapterTitle.toUpperCase(),
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
                                "DOWNLOADED FILES",
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
                          _buildTab("Videos (${videos.length})", 'videos'),
                          _buildTab("PDFs (${pdfs.length})", 'pdfs'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: activeTab == 'videos'
                  ? _buildFileList(videos, keys, LucideIcons.play)
                  : _buildFileList(pdfs, [], LucideIcons.fileText),
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

  Widget _buildFileList(List<Map<dynamic, dynamic>> files, List<dynamic> keys, IconData icon) {
    if (files.isEmpty) {
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
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        final key = keys.isNotEmpty ? keys[index] : null; // المفتاح للحذف
        
        // حساب الحجم
        final sizeBytes = item['size'] ?? 0;
        final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (activeTab == 'videos') {
                      _playOfflineVideo(item);
                    } else {
                      // فتح PDF (مستقبلاً)
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Opening PDF: ${item['title']}")));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundPrimary,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                          ),
                          child: Icon(icon, color: activeTab == 'videos' ? AppColors.accentOrange : AppColors.accentYellow, size: 14),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title'].toString().toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "$sizeMB MB",
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 32, color: Colors.white.withOpacity(0.05)),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 14, color: AppColors.accentOrange),
                onPressed: () {
                  if (key != null) _deleteFile(key.toString());
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
