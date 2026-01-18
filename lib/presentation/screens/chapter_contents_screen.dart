import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/download_manager.dart';
import 'video_player_screen.dart';
import 'youtube_player_screen.dart';
import 'pdf_viewer_screen.dart';

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
              
              // ✅ الخيار الأول (كان الثالث): المشغل المباشر
              _buildOptionTile(
                icon: LucideIcons.rocket, // أيقونة مميزة
                title: "First Player",
                subtitle: "High Performance Playback", // وصف عام
                onTap: () {
                  Navigator.pop(context);
                  _fetchAndPlayWithExplode(video); // استدعاء الدالة الجديدة
                },
              ),

              const SizedBox(height: 16),

              // ✅ الخيار الثاني: يوتيوب (كما هو)
              _buildOptionTile(
                icon: LucideIcons.youtube,
                title: "Second Player",
                subtitle: "Alternative Playback", // وصف عام
                onTap: () {
                  Navigator.pop(context);
                  _fetchAndPlayVideo(video, useYoutube: true);
                },
              ),
              
              const SizedBox(height: 16),

              // ✅ الخيار الثالث (كان الأول): المشغل القديم
              _buildOptionTile(
                icon: LucideIcons.playCircle,
                title: "Third Player",
                subtitle: "Standard Playback", // وصف عام
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

  // الدالة القديمة (للخيارين الثاني والثالث)
  Future<void> _fetchAndPlayVideo(Map<String, dynamic> video, {required bool useYoutube}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      var box = await Hive.openBox('auth_box');
      
      final res = await Dio().get(
        '$_baseUrl/api/secure/get-video-id',
        queryParameters: {'lessonId': video['id'].toString()},
        options: Options(headers: {
          'x-user-id': box.get('user_id'),
          'x-device-id': box.get('device_id'),
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

  // الدالة الجديدة للخيار الأول (الأقوى)
  Future<void> _fetchAndPlayWithExplode(Map<String, dynamic> video) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      var box = await Hive.openBox('auth_box');
      
      final res = await Dio().get(
        '$_baseUrl/api/secure/get-stream-proxy', 
        queryParameters: {'lessonId': video['id'].toString()},
        options: Options(headers: {
          'x-user-id': box.get('user_id'),
          'x-device-id': box.get('device_id'),
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
            _showErrorSnackBar("No playable streams found.");
          }
        } else {
          _showErrorSnackBar("Video streams unavailable.");
        }
      } else {
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      var box = await Hive.openBox('auth_box');
      
      final res = await Dio().get(
        '$_baseUrl/api/secure/get-stream-proxy', 
        queryParameters: {'lessonId': videoId},
        options: Options(headers: {
          'x-user-id': box.get('user_id'),
          'x-device-id': box.get('device_id'),
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
             _showErrorSnackBar("No compatible video streams found.");
          }
        } else {
          _showErrorSnackBar("No download links available");
        }
      } else {
        _showErrorSnackBar("Server Error: ${res.statusCode}");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorSnackBar("Failed to fetch download info");
    }
  }

  void _showQualitySelectionDialog(String videoId, String title, List<dynamic> qualities, String duration, String? audioUrl) {
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
                "SELECT DOWNLOAD QUALITY",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              ...qualities.map((q) {
                return ListTile(
                  leading: const Icon(LucideIcons.download, color: AppColors.accentYellow),
                  title: Text(
                    "${q['quality']}p", 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  // ✅ تم إزالة وصف الفيديو والصوت من هنا كما طلبت
                  trailing: const Icon(LucideIcons.chevronRight, color: Colors.white54, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    
                    String? targetAudio = (q['type'] == 'video_only') ? audioUrl : null;

                    _startVideoDownload(videoId, title, q['url'], targetAudio, "${q['quality']}p", duration);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _startVideoDownload(String videoId, String videoTitle, String? downloadUrl, String? audioUrl, String quality, String duration) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Started...")));
    
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
    final videos = (widget.chapter['videos'] as List? ?? []).cast<Map<String, dynamic>>();
    final pdfs = (widget.chapter['pdfs'] as List? ?? []).cast<Map<String, dynamic>>();

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

                        if (isDownloaded) return _buildStatusButton("SAVED", AppColors.success, LucideIcons.checkCircle);
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
