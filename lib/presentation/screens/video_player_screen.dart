import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';

class VideoPlayerScreen extends StatefulWidget {
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

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _userIdText = "User ID"; 

  @override
  void initState() {
    super.initState();
    
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _getUserId();
    _startWatermarkAnimation();
    _parseQualities();
  }

  void _getUserId() {
    try {
      if (Hive.isBoxOpen('auth_box')) {
        var box = Hive.box('auth_box');
        setState(() {
          _userIdText = box.get('phone') ?? box.get('username') ?? box.get('user_id') ?? 'Student';
        });
      }
    } catch (e) {}
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          double x = (random.nextDouble() * 1.6) - 0.8;
          double y = (random.nextDouble() * 1.6) - 0.8;
          _watermarkAlignment = Alignment(x, y);
        });
      }
    });
  }

  void _parseQualities() {
    if (widget.streams.isEmpty) {
      setState(() => _isError = true);
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    _currentQuality = _sortedQualities.contains("720p") ? "720p" : _sortedQualities.last;
    
    _initializePlayer(widget.streams[_currentQuality]!);
  }

  Future<void> _initializePlayer(String url) async {
    Duration currentPos = Duration.zero;
    if (_chewieController != null && _videoPlayerController.value.isInitialized) {
      currentPos = _videoPlayerController.value.position;
      _chewieController!.dispose();
      await _videoPlayerController.dispose();
    }

    try {
      // ✅ التعديل هنا: إضافة الهيدرز لإصلاح مشكلة التشغيل
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.youtube.com/',
          'Accept': '*/*',
        },
      );

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
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accentYellow,
            handleColor: AppColors.accentYellow,
            backgroundColor: Colors.grey,
            bufferedColor: Colors.white24,
          ),
          playbackSpeeds: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
          additionalOptions: (context) {
            return <OptionItem>[
              OptionItem(
                onTap: (context) {
                  Navigator.pop(context); 
                  _showQualitySheet();   
                },
                iconData: LucideIcons.settings,
                title: 'Quality: $_currentQuality',
              ),
            ];
          },
          errorBuilder: (context, errorMessage) {
            FirebaseCrashlytics.instance.log("Player Err: $errorMessage");
            return const Center(child: Text("Playback Error", style: TextStyle(color: Colors.white)));
          },
        );
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Init Error: $url');
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
              ..._sortedQualities.reversed.map((q) => ListTile(
                title: Text(q, style: TextStyle(color: q == _currentQuality ? AppColors.accentYellow : Colors.white)),
                trailing: q == _currentQuality ? const Icon(LucideIcons.check, color: AppColors.accentYellow) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (q != _currentQuality) {
                    setState(() {
                      _currentQuality = q;
                      _chewieController = null; 
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
    _watermarkTimer?.cancel();
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _isError
                ? const Text("Error loading video", style: TextStyle(color: AppColors.error))
                : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                    ? Chewie(controller: _chewieController!)
                    : const CircularProgressIndicator(color: AppColors.accentYellow),
          ),
          if (!_isError)
            AnimatedAlign(
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOut,
              alignment: _watermarkAlignment,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _userIdText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            top: 28,
            left: 70,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4)),
                child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
