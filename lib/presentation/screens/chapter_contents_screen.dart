import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/download_manager.dart';
import '../../core/services/storage_service.dart';
import 'video_player_screen.dart';
import 'youtube_player_screen.dart';
import 'pdf_viewer_screen.dart';
import 'teacher/manage_content_screen.dart'; // ✅ لاستخدامه في الإضافة والتعديل

class ChapterContentsScreen extends StatefulWidget {
  final Map<String, dynamic> chapter;
  final String courseTitle;
  final String subjectTitle;

  const ChapterContentsScreen({
    super.key, 
    required this.chapter,
    required this.courseTitle,
    required this.subjectTitle,
  });

  @override
  State<ChapterContentsScreen> createState() => _ChapterContentsScreenState();
}

class _ChapterContentsScreenState extends State<ChapterContentsScreen> {
  String activeTab = 'videos';
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';
  bool _isTeacher = false;
  // لتحديث المحتوى محلياً بعد الإضافة/التعديل
  late Map<String, dynamic> _currentChapter;

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.chapter;
    _checkUserRole();
  }

  // ✅ التحقق من الصلاحية
  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
      });
    }
  }

  // ✅ دالة لتحديث محتوى الشابتر من الكاش المحلي بعد التعديل
  Future<void> _refreshContent() async {
    try {
      // 1. فتح الصندوق الذي يحتوي على أحدث البيانات (التي حفظتها شاشة الإضافة)
      var box = await StorageService.openBox('teacher_data');
      List<dynamic> allContent = box.get('my_content', defaultValue: []);

      // 2. البحث عن الفصل الحالي داخل البيانات المحدثة
      Map<String, dynamic>? updatedChapter;

      // حلقة بحث للعثور على الشابتر المطابق للـ ID الحالي داخل الهيكل (كورسات -> مواد -> فصول)
      outerLoop:
      for (var course in allContent) {
        var subjects = (course['subjects'] as List? ?? []);
        for (var subject in subjects) {
          var chapters = (subject['chapters'] as List? ?? []);
          for (var chapter in chapters) {
            if (chapter['id'].toString() == widget.chapter['id'].toString()) {
              updatedChapter = Map<String, dynamic>.from(chapter);
              break outerLoop;
            }
          }
        }
      }

      // 3. تحديث الواجهة إذا وجدنا بيانات جديدة
      if (updatedChapter != null) {
        if (mounted) {
          setState(() {
            _currentChapter = updatedChapter!;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم تحديث المحتوى"), backgroundColor: AppColors.success, duration: Duration(milliseconds: 800)),
          );
        }
      }
    } catch (e) {
      debugPrint("Error refreshing content: $e");
    }
  }

  // ===========================================================================
  // 1. منطق المشاهدة (Watch Logic) واختيار المشغل
  // ===========================================================================

  void _showPlayerSelectionDialog(Map<String, dynamic> video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "SELECT PLAYER",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 24),
              
              _buildOptionTile(
                icon: LucideIcons.rocket, 
                title: "First Player",
                subtitle: "High Performance", 
                onTap: () {
                  Navigator.pop(context);
                  _fetchAndPlayWithExplode(video); 
                },
              ),

              const SizedBox(height: 16),

              _buildOptionTile(
                icon: LucideIcons.youtube,
                title: "Second Player",
                subtitle: "Standard Player", 
                onTap: () {
                  Navigator.pop(context);
                  _fetchAndPlayVideo(video, useYoutube: true);
                },
              ),
              
              const SizedBox(height: 16),

              _buildOptionTile(
                icon: LucideIcons.playCircle,
                title: "Third Player",
                subtitle: "Backup Player", 
                onTap: () {
                  Navigator.pop(context);
                  _fetchAndPlayVideo(video, useYoutube: false);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchAndPlayVideo(Map<String, dynamic> video, {required bool useYoutube}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      var box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');
      
      final res = await Dio().get(
        '$_baseUrl/api/secure/get-video-id',
        queryParameters: {'lessonId': video['id'].toString()},
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = res.data;
        final String videoTitle = data['db_video_title'] ?? video['title'];

        if (useYoutube) {
          String? youtubeId = data['youtube_video_id'];
          if (youtubeId != null && youtubeId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => YoutubePlayerScreen(videoId: youtubeId, title: videoTitle),
              ),
            );
          } else {
            FirebaseCrashlytics.instance.log("YouTube ID missing for lesson: ${video['id']}");
            _showErrorSnackBar("Not a YouTube video or ID missing.");
          }
        } else {
          Map<String, String> qualities = {};
          if (data['availableQualities'] != null) {
            for (var q in data['availableQualities']) {
              if (q['url'] != null) {
                qualities["${q['quality']}p"] = q['url'];
              }
            }
          }
          if (qualities.isEmpty && data['url'] != null) {
            qualities["Auto"] = data['url'];
          }

          if (qualities.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(streams: qualities, title: videoTitle),
              ),
            );
          } else {
            FirebaseCrashlytics.instance.log("No streamable URLs found for lesson: ${video['id']}");
            _showErrorSnackBar("No playable stream found.");
          }
        }
      } else {
        _showErrorSnackBar(res.data['message'] ?? "Access Denied");
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context);
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Play Video Exception');
      _showErrorSnackBar("Connection Error: Please check internet");
    }
  }

  Future<void> _fetchAndPlayWithExplode(Map<String, dynamic> video) async {
    FirebaseCrashlytics.instance.log("🚀 Starting Direct Play (Explode) for: ${video['title']}");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      var box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');
      
      final res = await Dio().get(
        '$_baseUrl/api/secure/get-stream-proxy', 
        queryParameters: {'lessonId': video['id'].toString()},
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = res.data;
        final String videoTitle = data['db_video_title'] ?? video['title'];
        final List<dynamic> rawQualities = data['availableQualities'] ?? [];

        if (rawQualities.isNotEmpty) {
          Map<String, String> processedQualities = {};

          String? bestAudioUrl;
          try {
            final audioObj = rawQualities.firstWhere(
              (q) => q['type'] == 'audio_only', 
              orElse: () => null
            );
            bestAudioUrl = audioObj?['url'];
          } catch (_) {}

          for (var item in rawQualities) {
            String url = item['url'];
            String qualityKey = "${item['quality']}p"; 
            String type = item['type']; 

            if (type == 'audio_only') continue;

            if (type == 'video_only' && bestAudioUrl != null) {
              processedQualities[qualityKey] = "$url|$bestAudioUrl";
            } else {
              processedQualities[qualityKey] = url;
            }
          }

          if (processedQualities.isNotEmpty) {
            FirebaseCrashlytics.instance.log("✅ Streams processed. Launching player.");
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  streams: processedQualities,
                  title: videoTitle,
                ),
              ),
            );
          } else {
            FirebaseCrashlytics.instance.log("⚠️ No valid video qualities processed.");
            _showErrorSnackBar("No playable streams found.");
          }
        } else {
          _showErrorSnackBar("Video streams unavailable.");
        }
      } else {
        FirebaseCrashlytics.instance.log("❌ Server Error: ${res.statusCode}");
        _showErrorSnackBar("Server Error: ${res.statusCode}");
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context);
      FirebaseCrashlytics.instance.recordError(e, stack, reason: "Direct Stream Error");
      _showErrorSnackBar("Connection Error or Timeout.");
    }
  }

  // ===========================================================================
  // 2. منطق التحميل (Download Logic)
  // ===========================================================================

  Future<void> _prepareVideoDownload(String videoId, String videoTitle, String duration) async {
    FirebaseCrashlytics.instance.log("⬇️ Fetching download info for: $videoTitle");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      var box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');
      
      final res = await Dio().get(
        '$_baseUrl/api/secure/get-stream-proxy', 
        queryParameters: {'lessonId': videoId},
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = res.data;
        List<dynamic> rawQualities = data['availableQualities'] ?? [];

        if (rawQualities.isNotEmpty) {
          
          String? bestAudioUrl;
          try {
            final audioObj = rawQualities.firstWhere((q) => q['type'] == 'audio_only', orElse: () => null);
            bestAudioUrl = audioObj?['url'];
          } catch (_) {}

          var videoOptions = rawQualities.where((q) => q['type'] != 'audio_only').toList();

          if (videoOptions.isNotEmpty) {
             _showQualitySelectionDialog(
               videoId, 
               videoTitle, 
               videoOptions, 
               duration, 
               bestAudioUrl 
             );
          } else {
             FirebaseCrashlytics.instance.log("⚠️ No video-only streams found for download.");
             _showErrorSnackBar("No compatible video streams found.");
          }
        } else {
          _showErrorSnackBar("No download links available");
        }
      } else {
        _showErrorSnackBar("Server Error: ${res.statusCode}");
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context);
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Prepare Download Failed');
      _showErrorSnackBar("Failed to fetch download info");
    }
  }

  void _showQualitySelectionDialog(String videoId, String title, List<dynamic> qualities, String duration, String? audioUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "SELECT DOWNLOAD QUALITY",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: qualities.map((q) {
                      return ListTile(
                        leading: const Icon(LucideIcons.download, color: AppColors.accentYellow),
                        title: Text(
                          "${q['quality']}p", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        trailing: const Icon(LucideIcons.chevronRight, color: Colors.white54, size: 16),
                        onTap: () {
                          Navigator.pop(context);
                          
                          String? targetAudio = (q['type'] == 'video_only') ? audioUrl : null;

                          _startVideoDownload(videoId, title, q['url'], targetAudio, "${q['quality']}p", duration);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startVideoDownload(String videoId, String videoTitle, String? downloadUrl, String? audioUrl, String quality, String duration) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Started...")));
    FirebaseCrashlytics.instance.log("⬇️ Starting download: $videoTitle ($quality)");
    
    DownloadManager().startDownload(
      lessonId: videoId,
      videoTitle: videoTitle,
      courseName: widget.courseTitle,
      subjectName: widget.subjectTitle,
      chapterName: widget.chapter['title'] ?? "Chapter",
      downloadUrl: downloadUrl,
      audioUrl: audioUrl,
      quality: quality,   
      duration: duration, 
      onProgress: (p) {},
      onComplete: () {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Completed!"), backgroundColor: AppColors.success));
      },
      onError: (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download Failed"), backgroundColor: AppColors.error));
      },
    );
  }

  void _startPdfDownload(String pdfId, String pdfTitle) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PDF Download Started...")));
      FirebaseCrashlytics.instance.log("⬇️ Starting PDF download: $pdfTitle");
      
      DownloadManager().startDownload(
      lessonId: pdfId, 
      videoTitle: pdfTitle, 
      courseName: widget.courseTitle, 
      subjectName: widget.subjectTitle,
      chapterName: widget.chapter['title'] ?? "Chapter",
      isPdf: true,
      quality: "PDF", 
      onProgress: (p) {},
      onComplete: () {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PDF Download Completed!"), backgroundColor: AppColors.success));
      },
      onError: (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download Failed"), backgroundColor: AppColors.error));
      },
    );
  }

  // ===========================================================================
  // UI Building Methods
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    // ✅ استخدام _currentChapter لضمان عرض البيانات المحدثة
    final videos = (_currentChapter['videos'] as List? ?? []).cast<Map<String, dynamic>>();
    final pdfs = (_currentChapter['pdfs'] as List? ?? []).cast<Map<String, dynamic>>();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: AppColors.backgroundPrimary.withOpacity(0.95),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.chapter['title'].toString().toUpperCase(),
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
                                Text(
                                  "${widget.courseTitle} > ${widget.subjectTitle}",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accentYellow.withOpacity(0.8),
                                    letterSpacing: 1.0,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ],
                        ),

                        // 🟢 زر الإضافة (يظهر للمعلم فقط)
                        if (_isTeacher)
                          GestureDetector(
                            onTap: () {
                              ContentType type = activeTab == 'videos' ? ContentType.video : ContentType.pdf;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ManageContentScreen(
                                    contentType: type,
                                    parentId: widget.chapter['id'].toString(), // ID الشابتر
                                  ),
                                ),
                              ).then((val) { 
                                // ✅ هنا يتم استدعاء التحديث الفوري
                                if(val == true) _refreshContent(); 
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.accentYellow.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: AppColors.accentYellow.withOpacity(0.5)),
                              ),
                              child: Icon(
                                activeTab == 'videos' ? LucideIcons.video : LucideIcons.filePlus, 
                                color: AppColors.accentYellow, size: 22
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Tabs
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
                          _buildTab("Videos", 'videos'),
                          _buildTab("PDFs", 'pdfs'),
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
                  ? _buildVideosList(videos)
                  : _buildPdfsList(pdfs),
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

  Widget _buildVideosList(List<Map<String, dynamic>> videos) {
    if (videos.isEmpty) return _buildEmptyState(LucideIcons.monitorPlay, "No video lessons");
    
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final String videoId = video['id'].toString();
        final String duration = video['duration'] ?? "--:--"; 
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                      ),
                      child: const Icon(LucideIcons.play, color: AppColors.accentOrange, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video['title'].toString().toUpperCase(),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "VIDEO", 
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary.withOpacity(0.7)),
                          ),
                        ],
                      ),
                    ),
                    
                    // 🟢 زر التعديل (للمعلم فقط)
                    if (_isTeacher)
                      IconButton(
                        icon: const Icon(LucideIcons.edit2, size: 18, color: AppColors.accentYellow),
                        onPressed: () {
                           Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageContentScreen(
                                contentType: ContentType.video,
                                initialData: video,
                                parentId: widget.chapter['id'].toString(),
                              ),
                            ),
                          ).then((val) { if(val == true) _refreshContent(); });
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      "Watch Now", 
                      AppColors.accentYellow, 
                      () => _showPlayerSelectionDialog(video), 
                    ),
                  ),
                  Container(width: 1, height: 48, color: Colors.white10),
                  
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: Hive.box('downloads_box').listenable(),
                      builder: (context, Box box, widget) {
                        bool isDownloaded = DownloadManager().isFileDownloaded(videoId);
                        bool isDownloading = DownloadManager().isFileDownloading(videoId);

                        String? sizeStr;
                        if (isDownloaded) {
                           final item = box.get(videoId);
                           if (item != null) {
                             int bytes = item['size'] ?? 0;
                             sizeStr = "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
                           }
                        }

                        if (isDownloaded) {
                           return _buildStatusButton("SAVED ${sizeStr != null ? '($sizeStr)' : ''}", AppColors.success, LucideIcons.checkCircle);
                        }
                        else if (isDownloading) return _buildStatusButton("LOADING...", AppColors.accentYellow, LucideIcons.loader);
                        else return _buildActionButton(
                          "Download", 
                          AppColors.textSecondary, 
                          () => _prepareVideoDownload(videoId, video['title'], duration)
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPdfsList(List<Map<String, dynamic>> pdfs) {
    if (pdfs.isEmpty) return _buildEmptyState(LucideIcons.fileText, "No PDF files");

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: pdfs.length,
      itemBuilder: (context, index) {
        final pdf = pdfs[index];
        final String pdfId = pdf['id'].toString();
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                      ),
                      child: const Icon(LucideIcons.fileText, color: AppColors.accentYellow, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pdf['title'].toString().toUpperCase(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text("STUDY MATERIAL", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary.withOpacity(0.7))),
                        ],
                      ),
                    ),
                    
                    // 🟢 زر التعديل (للمعلم فقط)
                    if (_isTeacher)
                      IconButton(
                        icon: const Icon(LucideIcons.edit2, size: 18, color: AppColors.accentYellow),
                        onPressed: () {
                           Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageContentScreen(
                                contentType: ContentType.pdf,
                                initialData: pdf,
                                parentId: widget.chapter['id'].toString(),
                              ),
                            ),
                          ).then((val) { if(val == true) _refreshContent(); });
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton("Open File", AppColors.accentYellow, () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfId: pdfId, title: pdf['title'])));
                    }),
                  ),
                  Container(width: 1, height: 48, color: Colors.white10),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: Hive.box('downloads_box').listenable(),
                      builder: (context, Box box, widget) {
                        bool isDownloaded = DownloadManager().isFileDownloaded(pdfId);
                        bool isDownloading = DownloadManager().isFileDownloading(pdfId);

                        if (isDownloaded) return _buildStatusButton("SAVED", AppColors.success, LucideIcons.checkCircle);
                        else if (isDownloading) return _buildStatusButton("LOADING...", AppColors.accentYellow, LucideIcons.loader);
                        else return _buildActionButton("Download", AppColors.textSecondary, () => _startPdfDownload(pdfId, pdf['title']));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Widgets مساعدة ---

  Widget _buildOptionTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accentYellow, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: color)),
        ),
      ),
    );
  }

  Widget _buildStatusButton(String label, Color color, IconData icon) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: color)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(message.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2.0, color: AppColors.textSecondary.withOpacity(0.5))),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.error));
  }
}
