import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart'; // ✅ المكتبة الجديدة
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:percent_indicator/percent_indicator.dart'; // ✅ لاستخدام شريط التقدم الدائري
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/local_proxy.dart'; // ✅ استيراد خدمة البروكسي
import '../../core/utils/encryption_helper.dart'; // ✅ ضروري لفك التشفير

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
  // ✅ استخدام خدمة البروكسي للبث المباشر للملفات المشفرة الكبيرة
  final LocalProxyService _proxyService = LocalProxyService();
  
  // متغيرات الحالة
  String? _proxyUrl;      // رابط التشغيل للأوفلاين (عبر البروكسي - للملفات الكبيرة)
  String? _localFilePath; // مسار الملف للأونلاين (بعد التحميل)
  Uint8List? _pdfBytes;   // ✅ بيانات الملف للأوفلاين (للملفات الصغيرة في الذاكرة)
  
  bool _loading = true;
  double _downloadProgress = 0.0; // ✅ نسبة التحميل للأونلاين
  bool _isOnlineDownload = false; // لتحديد نوع التحميل
  
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  
  String _watermarkText = '';
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("📄 PDF Screen Opened: ${widget.title} (ID: ${widget.pdfId})");
    _initWatermarkText();
    _loadPdf();
  }

  @override
  void dispose() {
    // ✅ إيقاف البروكسي عند الخروج
    _proxyService.stop();
    
    // ✅ حذف الملف المؤقت (فقط في حالة الأونلاين لأنه تم تحميله)
    if (_localFilePath != null) {
      final file = File(_localFilePath!);
      if (file.existsSync()) {
        try {
          file.deleteSync();
          FirebaseCrashlytics.instance.log("🔒 Temp online PDF deleted.");
        } catch (e) {
          FirebaseCrashlytics.instance.log("⚠️ Failed to delete temp PDF: $e");
        }
      }
    }
    super.dispose();
  }

  void _initWatermarkText() {
    String displayText = '';
    // 1. المحاولة الأولى: من الذاكرة الحية
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] ?? '';
    }
    // 2. المحاولة الثانية: من التخزين المحلي
    if (displayText.isEmpty) {
       try {
         if(Hive.isBoxOpen('auth_box')) {
           var box = Hive.box('auth_box');
           displayText = box.get('phone') ?? box.get('username') ?? '';
         }
       } catch(e) {
         FirebaseCrashlytics.instance.log("⚠️ Watermark load error: $e");
       }
    }
    setState(() => _watermarkText = displayText.isNotEmpty ? displayText : 'User');
  }

  /// دالة مساعدة لفك تشفير الملف بالكامل في الذاكرة (للملفات الصغيرة)
  Future<Uint8List> _decryptFileToMemory(File file) async {
    final builder = BytesBuilder();
    final raf = await file.open(mode: FileMode.read);
    
    try {
      final int fileLength = await file.length();
      int currentPos = 0;
      
      // استخدام الثوابت من EncryptionHelper
      const int blockSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;

      while (currentPos < fileLength) {
        int bytesToRead = blockSize;
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }

        Uint8List chunk = await raf.read(bytesToRead);
        if (chunk.isEmpty) break;

        // فك التشفير باستخدام الدالة السريعة
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
      // التأكد من تهيئة التشفير
      await EncryptionHelper.init();

      // ============================================================
      // 1. الأوفلاين: محاولة القراءة من التخزين المحلي
      // ============================================================
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final String encryptedPath = downloadItem['path'];
        final File encryptedFile = File(encryptedPath);
        
        if (await encryptedFile.exists()) {
          // ✅ التحسين الجديد: فحص حجم الملف
          int fileSize = await encryptedFile.length();
          
          // إذا كان الملف أصغر من 50 ميجابايت، نفك تشفيره في الرام (أسرع بكثير)
          if (fileSize < 50 * 1024 * 1024) { 
             try {
               FirebaseCrashlytics.instance.log("🚀 Loading small PDF to memory: $encryptedPath");
               final bytes = await _decryptFileToMemory(encryptedFile);
               
               if (mounted) {
                 setState(() {
                   _pdfBytes = bytes;
                   _loading = false;
                 });
               }
               return; // ✅ انتهينا، العرض من الذاكرة
             } catch (e) {
                // إذا فشلت الذاكرة، نكمل للكود التالي ونستخدم البروكسي كخطة بديلة
                FirebaseCrashlytics.instance.log("⚠️ Memory decrypt failed, falling back to proxy: $e");
             }
          }

          // --- الخطة ب: الملفات الكبيرة عبر البروكسي ---
          FirebaseCrashlytics.instance.log("📂 Opening Large/Offline PDF via Proxy: $encryptedPath");
          
          // تشغيل البروكسي
          await _proxyService.start();
          
          // تكوين رابط البروكسي
          final url = "http://127.0.0.1:8080/video?path=${Uri.encodeComponent(encryptedPath)}";
          
          if (mounted) {
            setState(() {
              _proxyUrl = url;
              _loading = false;
            });
          }
          return; 
        }
      }

      // ============================================================
      // 2. الأونلاين: تحميل مع شريط تقدم
      // ============================================================
      FirebaseCrashlytics.instance.log("☁️ Downloading Online PDF...");
      
      if (mounted) setState(() => _isOnlineDownload = true); // تفعيل وضع شريط التقدم

      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      final dio = Dio();
      final dir = await getTemporaryDirectory();
      // استخدام timestamp لضمان اسم فريد
      final savePath = '${dir.path}/online_${widget.pdfId}_${DateTime.now().millisecondsSinceEpoch}.pdf';

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
        // ✅ تحديث شريط التقدم
        onReceiveProgress: (received, total) {
          if (total != -1) {
            if (mounted) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          }
        },
      );

      if (mounted) {
        setState(() {
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
    // 1. حالة التحميل
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // إذا كان تحميل أونلاين نعرض شريط التقدم والنسبة
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
                // تحميل أوفلاين (سريع)
                const CircularProgressIndicator(color: AppColors.accentYellow),
              ]
            ],
          ),
        ),
      );
    }

    // 2. حالة الخطأ
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary, 
        appBar: AppBar(backgroundColor: Colors.transparent, leading: const BackButton(color: Colors.white)), 
        body: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
      );
    }

    // 3. العرض (النجاح)
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
          // ✅ العارض الجديد (SfPdfViewer)
          _buildPdfViewer(),

          // 2. العلامة المائية (طبقة متكررة) - ✅ تم الحفاظ عليها كما هي
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

          // 3. عداد الصفحات
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

  // دالة اختيار نوع العارض المناسب (ذاكرة / شبكة / ملف)
  Widget _buildPdfViewer() {
    // ✅ الحالة 1: ملف أوفلاين صغير (تم فكه للذاكرة) - الأسرع
    if (_pdfBytes != null) {
       return SfPdfViewer.memory(
        _pdfBytes!,
        key: _pdfViewerKey,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
        pageLayoutMode: PdfPageLayoutMode.continuous,
        onDocumentLoaded: (details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onPageChanged: (details) {
          setState(() => _currentPage = details.newPageNumber - 1);
        },
      );
    }
    // ✅ الحالة 2: ملف أوفلاين كبير (عبر البروكسي)
    else if (_proxyUrl != null) {
      return SfPdfViewer.network(
        _proxyUrl!,
        key: _pdfViewerKey,
        enableDoubleTapZooming: true,
        enableTextSelection: false, // منع النسخ
        pageLayoutMode: PdfPageLayoutMode.continuous,
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
    // ✅ الحالة 3: ملف أونلاين (تم تحميله مؤقتاً)
    else if (_localFilePath != null) {
      return SfPdfViewer.file(
        File(_localFilePath!),
        key: _pdfViewerKey,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
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

  // ✅ تصميم العلامة المائية (كما هو - بدون تغييرات)
  Widget _buildWatermarkItem() {
    return Transform.rotate(
      angle: -0.5, 
      child: Opacity(
        opacity: 0.15, // شفافية خفيفة
        child: Text(
          _watermarkText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.grey, // لون رمادي كما طلبت
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
