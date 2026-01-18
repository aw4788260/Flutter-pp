import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ استيراد Crashlytics
import '../../core/constants/app_colors.dart';
import 'video_player_screen.dart';
import 'pdf_viewer_screen.dart'; 

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

  @override
  void initState() {
    super.initState();
    // ✅ تسجيل دخول المستخدم للشاشة مع تفاصيل المكان
    FirebaseCrashlytics.instance.log(
      "📂 Opened Downloaded Chapter: ${widget.chapterTitle} (Course: ${widget.courseTitle})"
    );
  }

  // --- تشغيل الفيديو أوفلاين ---
  void _playOfflineVideo(Map<dynamic, dynamic> item) {
    try {
      final String filePath = item['path'] ?? '';
      
      if (filePath.isEmpty) {
        throw Exception("File path is null or empty for item: ${item['title']}");
      }

      FirebaseCrashlytics.instance.log("▶️ User requested offline video playback: ${item['title']}");
      FirebaseCrashlytics.instance.setCustomKey('offline_video_path', filePath);

      // ✅ التعديل الجذري: نمرر المسار الخام (Raw Path) بدلاً من رابط البروكسي
      // هذا يسمح لـ VideoPlayerScreen باكتشاف أنه ملف محلي وتشغيل منطق الصوت المدمج
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            streams: {"Offline": filePath}, 
            title: item['title'] ?? "Offline Video",
          ),
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to open offline video');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error opening video"), backgroundColor: AppColors.error),
      );
    }
  }

  // --- تشغيل PDF أوفلاين ---
  void _openOfflinePdf(String key, String title) {
    try {
      FirebaseCrashlytics.instance.log("📄 User requested offline PDF: $title (Key: $key)");
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            pdfId: key,
            title: title,
          ),
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to open offline PDF');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error opening PDF"), backgroundColor: AppColors.error),
      );
    }
  }

  // --- حذف الملف ---
  Future<void> _deleteFile(String key) async {
    try {
      FirebaseCrashlytics.instance.log("🗑️ User requested file deletion: $key");
      
      var box = await Hive.openBox('downloads_box');
      
      if (box.containsKey(key)) {
        await box.delete(key);
        FirebaseCrashlytics.instance.log("✅ File deleted successfully from Hive: $key");
      } else {
        FirebaseCrashlytics.instance.log("⚠️ File key not found in Hive during deletion: $key");
      }

      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("File removed"), backgroundColor: AppColors.accentOrange)
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to delete offline file');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to delete file"), backgroundColor: AppColors.error)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // استخدم ValueListenableBuilder لتحديث الواجهة تلقائياً عند الحذف دون الحاجة لـ setState يدوي
    return ValueListenableBuilder(
      valueListenable: Hive.box('downloads_box').listenable(),
      builder: (context, Box box, _) {
        
        List<Map<String, dynamic>> videoItems = [];
        List<Map<String, dynamic>> pdfItems = [];

        try {
          for (var key in box.keys) {
            final item = box.get(key);
            // تصفية العناصر بناءً على الهيكل الشجري (كورس > مادة > فصل)
            if (item['course'] == widget.courseTitle && 
                item['subject'] == widget.subjectTitle &&
                item['chapter'] == widget.chapterTitle) {
              
              final itemMap = Map<String, dynamic>.from(item);
              itemMap['key'] = key;

              if (item['type'] == 'pdf') {
                pdfItems.add(itemMap);
              } else {
                videoItems.add(itemMap);
              }
            }
          }
        } catch (e, stack) {
          FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error parsing Hive data in build');
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
        final key = item['key'];
        
        final sizeBytes = item['size'] ?? 0;
        final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
        final duration = item['duration'] ?? "--:--";
        
        // تحديد الجودة فقط إذا كان فيديو
        final quality = activeTab == 'videos' ? (item['quality'] ?? "SD") : null;

        return GestureDetector(
          onTap: () {
             if (activeTab == 'videos') {
               _playOfflineVideo(item);
             } else {
               _openOfflinePdf(key.toString(), item['title'] ?? 'Document');
             }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. الصف العلوي (أيقونة - عنوان - حذف)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: activeTab == 'videos' ? AppColors.accentOrange : AppColors.accentYellow, size: 20),
                    ),
                    const SizedBox(width: 14),
                    
                    Expanded(
                      child: Text(
                        item['title'].toString(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.2
                        ),
                        maxLines: 2, 
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    GestureDetector(
                      onTap: () => _deleteFile(key.toString()),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.transparent,
                        child: const Icon(LucideIcons.trash2, size: 18, color: AppColors.error),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 10),

                // 2. شريط المعلومات السفلي
                Row(
                  children: [
                    _buildMetaTag(LucideIcons.hardDrive, "$sizeMB MB"),
                    const SizedBox(width: 16),
                    
                    if(activeTab == 'videos') ...[
                      _buildMetaTag(LucideIcons.clock, duration),
                      const SizedBox(width: 16),
                      if (quality != null) _buildMetaTag(LucideIcons.monitor, quality),
                    ] else ...[
                       _buildMetaTag(LucideIcons.fileText, "PDF"),
                    ]
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textSecondary.withOpacity(0.7)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.9), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
