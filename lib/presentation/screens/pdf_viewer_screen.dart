import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart'; // ✅ العارض
import 'package:syncfusion_flutter_pdf/pdf.dart'; // ✅ للتشفير (للأونلاين فقط)
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:percent_indicator/percent_indicator.dart';
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
  String _filePassword = ""; // كلمة السر التي سيتم استخدامها لفك التشفير
  
  bool _loading = true;
  double _downloadProgress = 0.0;
  bool _isOnlineDownload = false; // لتحديد ما إذا كان الملف مؤقتاً
  
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  
  String _watermarkText = '';
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 📝 تسجيل دخول الشاشة
    FirebaseCrashlytics.instance.log("📄 PDF View: Started for ${widget.pdfId}");
    _initWatermarkText();
    _loadPdf();
  }

  @override
  void dispose() {
    // ✅ تنظيف الملفات المؤقتة فقط (في حالة الأونلاين)
    if (_isOnlineDownload && _localFilePath != null) {
      final file = File(_localFilePath!);
      if (file.existsSync()) {
        try {
          file.deleteSync();
          FirebaseCrashlytics.instance.log("🗑️ Temp online PDF deleted.");
        } catch (e) {
          FirebaseCrashlytics.instance.log("⚠️ Error deleting temp file: $e");
        }
      }
    }
    super.dispose();
  }

  // توليد كلمة سر عشوائية (للأونلاين فقط)
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
         FirebaseCrashlytics.instance.log("⚠️ Watermark Hive Error: $e");
       }
    }
    setState(() => _watermarkText = displayText.isNotEmpty ? displayText : 'User');
  }

  Future<void> _loadPdf() async {
    setState(() => _loading = true);
    try {
      // ============================================================
      // 1. الأوفلاين: البحث عن الملف وكلمة السر المخزنة
      // ============================================================
      if (!Hive.isBoxOpen('downloads_box')) {
        await Hive.openBox('downloads_box');
      }
      final downloadsBox = Hive.box('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null) {
        final String? path = downloadItem['path'];
        // ✅ الخطوة الحاسمة: جلب كلمة السر المخزنة لهذا الملف
        final String? storedPassword = downloadItem['file_password']; 

        if (path != null) {
          final File file = File(path);
          if (await file.exists()) {
            FirebaseCrashlytics.instance.log("📂 Offline PDF Found: $path");

            if (storedPassword != null && storedPassword.isNotEmpty) {
              // ✅ الحالة المثالية: الملف موجود وكلمة السر موجودة
              if (mounted) {
                setState(() {
                  _localFilePath = path;
                  _filePassword = storedPassword; // استخدام كلمة السر المخزنة لفك التشفير
                  _loading = false;
                  _isOnlineDownload = false; // لا نحذف الملف عند الخروج
                });
              }
              return; // انتهينا، لا تكمل للأونلاين
            } else {
              // ⚠️ الملف موجود لكن بدون كلمة سر (ملفات قديمة قبل التحديث)
              FirebaseCrashlytics.instance.recordError(
                Exception("Legacy PDF found without password"), 
                null, 
                reason: "Legacy File Support"
              );
              
              if (mounted) {
                setState(() {
                  _error = "Old file version. Please delete and re-download.";
                  _loading = false;
                });
              }
              return;
            }
          } else {
            FirebaseCrashlytics.instance.log("⚠️ Record exists but file missing: $path");
          }
        }
      }

      // ============================================================
      // 2. الأونلاين: التحميل والتشفير المؤقت
      // ============================================================
      FirebaseCrashlytics.instance.log("☁️ Switching to Online Download...");
      await _downloadAndSecurePdf();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'CRITICAL: _loadPdf Failed');
      if (mounted) {
        setState(() { 
          _error = "Error loading PDF: $e"; 
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

      // 1. تحميل
      FirebaseCrashlytics.instance.log("⬇️ Downloading raw PDF...");
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

      // 2. تشفير (للأونلاين فقط)
      if (mounted) setState(() => _downloadProgress = 1.0); 
      FirebaseCrashlytics.instance.log("🔐 Encrypting Online PDF...");
      
      final File rawFile = File(rawPath);
      final List<int> bytes = await rawFile.readAsBytes();
      
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      // توليد كلمة سر عشوائية لهذه الجلسة
      final String sessionPassword = _generateRandomPassword();
      
      document.security.userPassword = sessionPassword;
      document.security.ownerPassword = _generateRandomPassword(); 
      document.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
      
      final List<int> encryptedBytes = await document.save();
      document.dispose();
      
      await File(securePath).writeAsBytes(encryptedBytes);
      
      // حذف الخام
      if (await rawFile.exists()) await rawFile.delete();

      if (mounted) {
        setState(() {
          _localFilePath = securePath;
          _filePassword = sessionPassword; // استخدام كلمة السر المؤقتة
          _loading = false;
        });
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Online Download/Encrypt Failed');
      throw Exception("Download failed: $e");
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
          // ✅ 1. العارض (يفتح الملف باستخدام كلمة السر)
          if (_localFilePath != null)
            SfPdfViewer.file(
              File(_localFilePath!),
              key: _pdfViewerKey,
              password: _filePassword, // 🔐 المفتاح لفك التشفير
              enableDoubleTapZooming: true,
              enableTextSelection: false,
              pageLayoutMode: PdfPageLayoutMode.continuous,
              onDocumentLoaded: (details) {
                FirebaseCrashlytics.instance.log("✅ PDF Rendered Successfully");
                setState(() => _totalPages = details.document.pages.count);
              },
              onPageChanged: (details) {
                setState(() => _currentPage = details.newPageNumber - 1);
              },
              onDocumentLoadFailed: (details) {
                String err = "Failed to render: ${details.error}";
                // 🚨 تسجيل خطأ العرض (مثل كلمة سر خاطئة)
                FirebaseCrashlytics.instance.recordError(
                  details.error, 
                  null, 
                  reason: 'SfPdfViewer Load Failed',
                  information: [
                    'File Path: $_localFilePath',
                    'Is Online Download: $_isOnlineDownload',
                    'Password Length: ${_filePassword.length}'
                  ]
                );
                setState(() => _error = err);
              },
            ),

          // ✅ 2. العلامة المائية
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
