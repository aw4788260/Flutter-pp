import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart'; // ✅ العارض السريع
import 'package:syncfusion_flutter_pdf/pdf.dart'; // ✅ لتشفير الملفات
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:percent_indicator/percent_indicator.dart'; // ✅ شريط التقدم
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';

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
  // متغيرات المسار وكلمة السر
  String? _localFilePath;
  String _filePassword = ""; // ✅ كلمة السر التي سيتم استخدامها لفتح الملف
  
  bool _loading = true;
  double _downloadProgress = 0.0;
  bool _isOnlineDownload = false;
  
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  
  String _watermarkText = '';
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("📄 PDF Screen: ${widget.title}");
    _initWatermarkText();
    _loadPdf();
  }

  @override
  void dispose() {
    // ✅ تنظيف الملفات المؤقتة عند الخروج (للأونلاين فقط)
    if (_isOnlineDownload && _localFilePath != null) {
      final file = File(_localFilePath!);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (e) {
          debugPrint("Error deleting temp file: $e");
        }
      }
    }
    super.dispose();
  }

  // توليد كلمة سر عشوائية قوية للملفات المؤقتة
  String _generateRandomPassword() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(values);
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
       } catch(e) {
         // ignore
       }
    }
    setState(() => _watermarkText = displayText.isNotEmpty ? displayText : 'User');
  }

  Future<void> _loadPdf() async {
    setState(() => _loading = true);
    try {
      // ============================================================
      // 1. محاولة الفتح من الأوفلاين (الملفات المحملة سابقاً)
      // ============================================================
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final File file = File(downloadItem['path']);
        if (await file.exists()) {
          // ✅ جلب كلمة السر المخزنة الخاصة بهذا الملف
          String? storedPassword = downloadItem['file_password'];
          
          if (storedPassword == null || storedPassword.isEmpty) {
             // ⚠️ تعامل مع الملفات القديمة (قبل التحديث)
             // يمكنك هنا وضع كلمة سر افتراضية أو إظهار رسالة خطأ تطلب إعادة التحميل
             _error = "Old file format. Please delete and re-download.";
             setState(() => _loading = false);
             return;
          }

          if (mounted) {
            setState(() {
              _localFilePath = file.path;
              _filePassword = storedPassword; // استخدام كلمة السر المخزنة
              _loading = false;
            });
          }
          return; 
        }
      }

      // ============================================================
      // 2. الأونلاين: تحميل + تشفير مؤقت + عرض
      // ============================================================
      await _downloadAndSecurePdf();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF Load Failed');
      if (mounted) {
        setState(() { 
          _error = "Failed to open PDF: $e"; 
          _loading = false; 
        });
      }
    }
  }

  Future<void> _downloadAndSecurePdf() async {
    setState(() => _isOnlineDownload = true);
    
    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      final dio = Dio();
      final dir = await getTemporaryDirectory();
      
      // مسارات مؤقتة
      final rawPath = '${dir.path}/raw_${widget.pdfId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final securePath = '${dir.path}/secure_${widget.pdfId}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // 1. تحميل الملف الخام
      await dio.download(
        'https://courses.aw478260.dpdns.org/api/secure/get-pdf',
        rawPath,
        queryParameters: {'pdfId': widget.pdfId},
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      // 2. تشفير الملف بكلمة سر عشوائية
      if (mounted) setState(() => _downloadProgress = 1.0); // مرحلة المعالجة
      
      final File rawFile = File(rawPath);
      final List<int> bytes = await rawFile.readAsBytes();
      
      // إنشاء مستند PDF ومعالجته
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      // توليد كلمة سر عشوائية لهذه الجلسة فقط
      final String sessionPassword = _generateRandomPassword();
      
      document.security.userPassword = sessionPassword;
      document.security.ownerPassword = _generateRandomPassword(); // كلمة مالك مختلفة
      document.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
      
      // حفظ النسخة المشفرة
      final List<int> encryptedBytes = await document.save();
      document.dispose();
      
      await File(securePath).writeAsBytes(encryptedBytes);
      
      // حذف النسخة الخام فوراً
      if (await rawFile.exists()) await rawFile.delete();

      if (mounted) {
        setState(() {
          _localFilePath = securePath;
          _filePassword = sessionPassword; // تعيين كلمة السر للعرض
          _loading = false;
        });
      }

    } catch (e) {
      throw Exception("Download/Encryption failed: $e");
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
                const Text("Securing Document...", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
        body: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center))
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
          // ✅ 1. العارض (يستخدم كلمة السر مباشرة)
          if (_localFilePath != null)
            SfPdfViewer.file(
              File(_localFilePath!),
              key: _pdfViewerKey,
              password: _filePassword, // 🔐 المفتاح السحري للسرعة
              enableDoubleTapZooming: true,
              enableTextSelection: false,
              pageLayoutMode: PdfPageLayoutMode.continuous,
              onDocumentLoaded: (details) {
                setState(() => _totalPages = details.document.pages.count);
              },
              onPageChanged: (details) {
                setState(() => _currentPage = details.newPageNumber - 1);
              },
              onDocumentLoadFailed: (details) {
                setState(() => _error = "Failed to render: ${details.error}");
                FirebaseCrashlytics.instance.recordError(details.error, null, reason: 'SfPdfViewer Failed');
              },
            ),

          // ✅ 2. العلامة المائية (ثابتة)
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
