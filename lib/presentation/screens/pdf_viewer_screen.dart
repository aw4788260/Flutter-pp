import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/encryption_helper.dart'; // ✅ استيراد مساعد التشفير

class PdfViewerScreen extends StatefulWidget {
  final String pdfId;
  final String title;

  const PdfViewerScreen({super.key, required this.pdfId, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  File? _tempDecryptedFile; // ✅ متغير لحفظ الملف المفكوك مؤقتاً
  bool _loading = true;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  
  String _watermarkText = '';

  @override
  void initState() {
    super.initState();
    _initWatermarkText();
    _loadPdf();
  }

  @override
  void dispose() {
    // ✅ تنظيف أمني: حذف الملف المفكوك عند الخروج من الشاشة
    if (_tempDecryptedFile != null && _tempDecryptedFile!.existsSync()) {
      try {
        _tempDecryptedFile!.deleteSync();
        debugPrint("🔒 Temp decrypted PDF deleted.");
      } catch (e) {
        debugPrint("Failed to delete temp PDF: $e");
      }
    }
    super.dispose();
  }

  void _initWatermarkText() {
    String phone = '';
    // محاولة جلب رقم الهاتف من الذاكرة الحية أو التخزين المحلي
    if (AppState().userData != null) {
      phone = AppState().userData!['phone'] ?? '';
    } 
    if (phone.isEmpty) {
       try {
         if(Hive.isBoxOpen('auth_box')) {
           var box = Hive.box('auth_box');
           phone = box.get('phone') ?? '';
         }
       } catch(_) {}
    }
    setState(() {
      _watermarkText = phone.isNotEmpty ? phone : 'User';
    });
  }

  Future<void> _loadPdf() async {
    setState(() => _loading = true);
    try {
      // ✅ 1. التحقق أولاً: هل الملف محمل ومشفر محلياً؟
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final File encryptedFile = File(downloadItem['path']);
        
        if (await encryptedFile.exists()) {
          FirebaseCrashlytics.instance.log("📂 Found encrypted PDF offline: ${widget.pdfId}");
          
          // تحديد مسار مؤقت لفك التشفير
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/${widget.pdfId}_temp.pdf';
          
          // فك التشفير
          await EncryptionHelper.init();
          await EncryptionHelper.decryptFileFull(encryptedFile, tempPath);
          
          if (mounted) {
            setState(() {
              _localPath = tempPath;
              _tempDecryptedFile = File(tempPath);
              _loading = false;
            });
          }
          return; // انتهينا، لا داعي للتحميل من النت
        }
      }

      // ✅ 2. إذا لم يكن موجوداً محلياً، قم بتحميله من السيرفر (كاش عادي)
      FirebaseCrashlytics.instance.log("☁️ Fetching PDF from server: ${widget.pdfId}");
      
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/cached_pdfs');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final file = File('${cacheDir.path}/${widget.pdfId}.pdf');
      bool useCachedFile = false;

      // التحقق من صلاحية الكاش (مثلاً 10 أيام)
      if (await file.exists()) {
        final lastModified = await file.lastModified();
        if (DateTime.now().difference(lastModified).inDays < 10) {
          useCachedFile = true;
        } else {
          await file.delete(); 
        }
      }

      if (useCachedFile) {
        if (mounted) setState(() { _localPath = file.path; _loading = false; });
      } else {
        await _downloadAndSavePdf(file);
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF Load Failed');
      if (mounted) setState(() { _error = "Failed to open PDF"; _loading = false; });
    }
  }

  Future<void> _downloadAndSavePdf(File targetFile) async {
    var box = await Hive.openBox('auth_box');
    final userId = box.get('user_id');
    final deviceId = box.get('device_id');

    final dio = Dio();
    final response = await dio.get(
      'https://courses.aw478260.dpdns.org/api/secure/get-pdf',
      queryParameters: {'pdfId': widget.pdfId},
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'x-user-id': userId,
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        },
      ),
    );

    final bytes = response.data as Uint8List;
    await targetFile.writeAsBytes(bytes, flush: true);

    if (mounted) {
      setState(() {
        _localPath = targetFile.path;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_error != null) return Scaffold(backgroundColor: AppColors.backgroundPrimary, appBar: AppBar(backgroundColor: Colors.transparent, leading: const BackButton(color: Colors.white)), body: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))));

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
      ),
      body: Stack(
        children: [
          // 1. عارض PDF
          PDFView(
            filePath: _localPath,
            enableSwipe: true,
            swipeHorizontal: false, // التمرير العمودي أفضل للقراءة
            autoSpacing: false,
            pageFling: false,
            backgroundColor: AppColors.backgroundPrimary,
            onRender: (pages) => setState(() { _totalPages = pages!; _isReady = true; }),
            onViewCreated: (controller) {},
            onPageChanged: (page, total) => setState(() => _currentPage = page!),
            onError: (error) {
              setState(() => _error = error.toString());
            },
          ),

          // 2. العلامة المائية (طبقة فوق الـ PDF)
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
          if (_isReady)
            Positioned(
              bottom: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${_currentPage + 1} / $_totalPages",
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ودجت لبناء سطر من العلامات المائية لضمان تغطية الشاشة
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
      angle: -0.5, // زاوية ميلان
      child: Opacity(
        opacity: 0.15, // شفافية خفيفة حتى لا تعيق القراءة
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
