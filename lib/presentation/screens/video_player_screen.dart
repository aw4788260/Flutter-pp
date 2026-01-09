import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';

class VideoPlayerScreen extends StatefulWidget {
  // نستقبل قائمة الجودات { "1080p": "url", "720p": "url" }
  final Map<String, String> streams; 
  final String title;

  const VideoPlayerScreen({super.key, required this.streams, required this.title});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  
  String _currentQuality = "";
  List<String> _sortedQualities = [];

  @override
  void initState() {
    super.initState();
    _parseQualities();
  }

  void _parseQualities() {
    if (widget.streams.isEmpty) {
      setState(() => _isError = true);
      return;
    }

    // ترتيب الجودات رقمياً (مثلاً 360, 720, 1080)
    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      // استخراج الرقم من النص (مثلاً "720p" -> 720)
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    // البدء بأفضل جودة (آخر عنصر في القائمة المرتبة تصاعدياً)
    // أو يمكن البدء بـ 720p (أو 480p) لتوفير البيانات إذا توفرت
    _currentQuality = _sortedQualities.contains("720p") ? "720p" : _sortedQualities.last;
    
    _initializePlayer(widget.streams[_currentQuality]!);
  }

  Future<void> _initializePlayer(String url) async {
    // حفظ مكان التوقف الحالي لاستكمال المشاهدة عند تغيير الجودة
    Duration currentPos = Duration.zero;
    if (_chewieController != null && _videoPlayerController.value.isInitialized) {
      currentPos = _videoPlayerController.value.position;
      _chewieController!.dispose();
      await _videoPlayerController.dispose();
    }

    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoPlayerController.initialize();
      
      if (currentPos > Duration.zero) {
        await _videoPlayerController.seekTo(currentPos);
      }

      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoPlayerController,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          showControls: true,
          
          // تخصيص الألوان
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accentYellow,
            handleColor: AppColors.accentYellow,
            backgroundColor: Colors.grey,
            bufferedColor: Colors.white24,
          ),
          
          // سرعات التشغيل
          playbackSpeeds: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
          
          // إضافة زر "الإعدادات" في الشريط العلوي للمشغل
          additionalOptions: (context) {
            return <OptionItem>[
              OptionItem(
                // ✅ تم التصحيح: إضافة context للمعامل
                onTap: (context) {
                  Navigator.pop(context); // إغلاق قائمة الخيارات الأساسية
                  _showQualitySheet();    // فتح قائمة الجودات
                },
                iconData: LucideIcons.settings,
                title: 'Quality: $_currentQuality',
              ),
            ];
          },
          
          errorBuilder: (context, errorMessage) {
            return Center(child: Text(errorMessage, style: const TextStyle(color: Colors.white)));
          },
        );
      });
    } catch (e) {
      setState(() => _isError = true);
    }
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Quality", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              // نعرض القائمة معكوسة لتكون أعلى جودة في الأعلى
              ..._sortedQualities.reversed.map((q) => ListTile(
                title: Text(q, style: TextStyle(color: q == _currentQuality ? AppColors.accentYellow : Colors.white)),
                trailing: q == _currentQuality ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (q != _currentQuality) {
                    setState(() {
                      _currentQuality = q;
                      _chewieController = null; // إظهار مؤشر التحميل
                    });
                    _initializePlayer(widget.streams[q]!);
                  }
                },
              )),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
      body: Center(
        child: _isError
            ? const Text("Error loading video", style: TextStyle(color: AppColors.error))
            : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: AppColors.accentYellow),
      ),
    );
  }
}
