import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:device_info_plus/device_info_plus.dart'; 
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/local_proxy.dart';
import '../../core/utils/encryption_helper.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfId;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.pdfId,
    required this.title
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final LocalProxyService _proxyService = LocalProxyService();
  
  String? _proxyUrl;
  String? _localFilePath;
  Uint8List? _pdfBytes;
  
  bool _loading = true;
  double _downloadProgress = 0.0;
  bool _isOnlineDownload = false;
  
  // متغير لتحديد ما إذا كان الجهاز ضعيفاً جداً (لتقليل استهلاك الذاكرة فقط عند الضرورة القصوى)
  bool _isWeakDevice = false;

  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  
  String _watermarkText = '';
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("📄 PDF Screen Opened: ${widget.title}");
    _checkDevicePerformance();
    _initWatermarkText();
    _loadPdf();
  }

  Future<void> _checkDevicePerformance() async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        // الأجهزة القديمة (Android 9 وأقل)
        if (androidInfo.version.sdkInt <= 28) {
          if (mounted) setState(() => _isWeakDevice = true);
        }
      } catch (e) {
        // تجاهل الخطأ
      }
    }
  }

  @override
  void dispose() {
    _proxyService.stop();
    
    // حذف الملف المؤقت عند الخروج لتوفير المساحة
    if (_localFilePath != null) {
      final file = File(_localFilePath!);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (e) { /* ignore */ }
      }
    }
    super.dispose();
  }

  void _initWatermarkText() {
    String displayText = '';
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] ?? '';
    }
    if (displayText.isEmpty) {
       try {
         if(Hive.isBoxOpen('auth_box')) {
           var box = Hive.box('auth_box');
           displayText = box.get('phone') ?? box.get('username') ?? '';
         }
       } catch(e) { /* ignore */ }
    }
    setState(() => _watermarkText = displayText.isNotEmpty ? displayText : 'User');
  }

  // دالة فك التشفير في الذاكرة (سريعة للملفات الصغيرة)
  Future<Uint8List> _decryptFileToMemory(File file) async {
    final builder = BytesBuilder();
    final raf = await file.open(mode: FileMode.read);
    
    try {
      final int fileLength = await file.length();
      int currentPos = 0;
      const int blockSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;

      while (currentPos < fileLength) {
        int bytesToRead = blockSize;
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }

        Uint8List chunk = await raf.read(bytesToRead);
        if (chunk.isEmpty) break;

        Uint8List decryptedChunk = EncryptionHelper.decryptBlock(chunk);
        builder.add(decryptedChunk);

        currentPos += chunk.length;
      }
    } finally {
      await raf.close();
    }
    return builder.toBytes();
  }

  Future<void> _loadPdf() async {
    setState(() => _loading = true);
    try {
      await EncryptionHelper.init();

      // ==========================================
      // 1. التعامل مع الملفات الأوفلاين (المحملة مسبقاً)
      // ==========================================
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final String encryptedPath = downloadItem['path'];
        final File encryptedFile = File(encryptedPath);
        
        if (await encryptedFile.exists()) {
          int fileSize = await encryptedFile.length();
          
          // إذا الملف صغير (أقل من 30 ميجا)، نفك تشفيره في الرام لأنه أسرع وأسلس في التمرير
          // قللنا الحد لـ 30 مراعاة للأجهزة القديمة
          if (fileSize < 30 * 1024 * 1024) { 
             try {
               final bytes = await _decryptFileToMemory(encryptedFile);
               if (mounted) {
                 setState(() {
                   _pdfBytes = bytes;
                   _loading = false;
                 });
               }
               return;
             } catch (e) {
                FirebaseCrashlytics.instance.log("⚠️ Memory decrypt failed, switching to proxy: $e");
             }
          }

          // الملفات الكبيرة نستخدم معها البروكسي لتجنب امتلاء الذاكرة
          await _proxyService.start();
          // نستخدم منفذ الفيديو (8080) أو الصوت (8081) كلاهما يعمل، نستخدم 8080 هنا
          final url = "http://127.0.0.1:8080/video?path=${Uri.encodeComponent(encryptedPath)}&type=.pdf";
          
          if (mounted) {
            setState(() {
              _proxyUrl = url;
              _loading = false;
            });
          }
          return; 
        }
      }

      // ==========================================
      // 2. التحميل من الإنترنت (Online)
      // ==========================================
      if (mounted) setState(() => _isOnlineDownload = true);

      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/online_${widget.pdfId}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // ✅ متغير للتحكم في معدل تحديث الشاشة (Throttling)
      // هذا هو الإصلاح الرئيسي لمشكلة "ثقل" الجهاز وتوقفه
      int lastUpdateTimestamp = 0;

      await dio.download(
        'https://courses.aw478260.dpdns.org/api/secure/get-pdf',
        savePath,
        queryParameters: {'pdfId': widget.pdfId},
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
            // ✅ التحديث فقط إذا مر 250 ميلي ثانية (ربع ثانية) منذ آخر تحديث
            // هذا يمنع استدعاء setState آلاف المرات في الثانية
            if (currentTimestamp - lastUpdateTimestamp > 250) {
              lastUpdateTimestamp = currentTimestamp;
              if (mounted) {
                setState(() {
                  _downloadProgress = received / total;
                });
              }
            }
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadProgress = 1.0;
          _localFilePath = savePath;
          _loading = false;
        });
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF Load Failed');
      if (mounted) {
        setState(() { 
          _error = "Failed to load PDF. Please check internet."; 
          _loading = false; 
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isOnlineDownload) ...[
                CircularPercentIndicator(
                  radius: 40.0,
                  lineWidth: 5.0,
                  percent: _downloadProgress,
                  center: Text(
                    "${(_downloadProgress * 100).toInt()}%",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                  ),
                  progressColor: AppColors.accentYellow,
                  backgroundColor: Colors.white10,
                ),
                const SizedBox(height: 16),
                const Text("Downloading PDF...", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ] else ...[
                const CircularProgressIndicator(color: AppColors.accentYellow),
              ]
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary, 
        appBar: AppBar(backgroundColor: Colors.transparent, leading: const BackButton(color: Colors.white)), 
        body: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow), 
          onPressed: () => Navigator.pop(context)
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.search, color: Colors.white),
            onPressed: () {
              _pdfViewerKey.currentState?.openBookmarkView();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildPdfViewer(),

          // العلامة المائية
          IgnorePointer(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildWatermarkRow(),
                  _buildWatermarkRow(),
                  _buildWatermarkRow(),
                  _buildWatermarkRow(),
                ],
              ),
            ),
          ),

          // رقم الصفحة
          Positioned(
            bottom: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _totalPages > 0 ? "${_currentPage + 1} / $_totalPages" : "${_currentPage + 1}",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    // ✅ تم إرجاع الوضع المستمر (Continuous) ليعرض الصفحات أسفل بعضها كما طلبت
    // ولكن قمنا بتحسين الأداء عبر إدارة الذاكرة في _loadPdf وعبر تقييد التحديثات
    const layoutMode = PdfPageLayoutMode.continuous;
    const scrollDirection = PdfScrollDirection.vertical;

    if (_pdfBytes != null) {
       return SfPdfViewer.memory(
        _pdfBytes!,
        key: _pdfViewerKey,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
        pageLayoutMode: layoutMode, 
        scrollDirection: scrollDirection,
        onDocumentLoaded: (details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onPageChanged: (details) {
          setState(() => _currentPage = details.newPageNumber - 1);
        },
      );
    }
    else if (_proxyUrl != null) {
      return SfPdfViewer.network(
        _proxyUrl!,
        key: _pdfViewerKey,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
        pageLayoutMode: layoutMode,
        scrollDirection: scrollDirection,
        onDocumentLoaded: (details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onPageChanged: (details) {
          setState(() => _currentPage = details.newPageNumber - 1);
        },
        onDocumentLoadFailed: (details) {
          setState(() => _error = "Failed to render PDF: ${details.error}");
        },
      );
    } 
    else if (_localFilePath != null) {
      return SfPdfViewer.file(
        File(_localFilePath!),
        key: _pdfViewerKey,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
        pageLayoutMode: layoutMode,
        scrollDirection: scrollDirection,
        onDocumentLoaded: (details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onPageChanged: (details) {
          setState(() => _currentPage = details.newPageNumber - 1);
        },
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildWatermarkRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildWatermarkItem(),
        _buildWatermarkItem(),
      ],
    );
  }

  Widget _buildWatermarkItem() {
    return Transform.rotate(
      angle: -0.5, 
      child: Opacity(
        opacity: 0.15,
        child: Text(
          _watermarkText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.grey,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
