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
  String? _localPath;
  File? _tempDecryptedFile; // ✅ مرجع للملف المؤقت لحذفه عند الخروج
  bool _loading = true;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  
  String _watermarkText = '';

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("📄 PDF Screen Opened: ${widget.title} (ID: ${widget.pdfId})");
    _initWatermarkText();
    _loadPdf();
  }

  @override
  void dispose() {
    // ✅ تنظيف أمني: حذف الملف المفكوك عند الخروج من الشاشة
    if (_tempDecryptedFile != null && _tempDecryptedFile!.existsSync()) {
      try {
        _tempDecryptedFile!.deleteSync();
        FirebaseCrashlytics.instance.log("🔒 Temp decrypted PDF deleted successfully.");
      } catch (e) {
        FirebaseCrashlytics.instance.log("⚠️ Failed to delete temp PDF: $e");
      }
    }
    super.dispose();
  }

  void _initWatermarkText() {
    String displayText = '';
    
    // 1. المحاولة الأولى: من الذاكرة الحية (الأسرع)
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

    setState(() {
      _watermarkText = displayText.isNotEmpty ? displayText : 'User';
    });
  }

  Future<void> _loadPdf() async {
    setState(() => _loading = true);
    try {
      // ============================================================
      // 1. محاولة الفتح من الملفات المحملة محلياً (Offline)
      // ============================================================
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final String encryptedPath = downloadItem['path'];
        final File encryptedFile = File(encryptedPath);
        
        if (await encryptedFile.exists()) {
          FirebaseCrashlytics.instance.log("📂 Found encrypted PDF offline at: $encryptedPath");
          
          // تحديد مسار مؤقت لفك التشفير
          final tempDir = await getTemporaryDirectory();
          // استخدام timestamp لضمان اسم فريد وتجنب التداخل
          final tempPath = '${tempDir.path}/temp_${widget.pdfId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
          final tempFile = File(tempPath);

          try {
            // ✅ فك التشفير
            await EncryptionHelper.init();
            await EncryptionHelper.decryptFileFull(encryptedFile, tempPath);
            FirebaseCrashlytics.instance.log("🔓 PDF Decrypted successfully to: $tempPath");
            
            if (mounted) {
              setState(() {
                _localPath = tempPath;
                _tempDecryptedFile = tempFile; // حفظ المرجع للحذف لاحقاً
                _loading = false;
              });
            }
            return; // ✅ تم الفتح بنجاح من الأوفلاين، نخرج من الدالة
          } catch (e, stack) {
            FirebaseCrashlytics.instance.recordError(e, stack, reason: '🔥 PDF Decryption Failed');
            // لا نتوقف هنا، نحاول التحميل من السيرفر كخيار بديل (Fallback)
          }
        } else {
          FirebaseCrashlytics.instance.log("⚠️ Offline record found but file missing on disk: $encryptedPath");
        }
      }

      // ============================================================
      // 2. التحميل المباشر من السيرفر (Online Fallback)
      // ============================================================
      FirebaseCrashlytics.instance.log("☁️ Fetching PDF from Online API...");
      
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

      if (response.statusCode == 200) {
        final bytes = response.data as Uint8List;
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/online_${widget.pdfId}_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await file.writeAsBytes(bytes, flush: true);

        FirebaseCrashlytics.instance.log("✅ PDF Downloaded Online: ${bytes.length} bytes");

        if (mounted) {
          setState(() {
            _localPath = file.path;
            _tempDecryptedFile = file; // أيضاً نحذفه عند الخروج
            _loading = false;
          });
        }
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: '🚨 Final PDF Load Failed');
      if (mounted) {
        setState(() { 
          _error = "Failed to load PDF. Please check your connection."; 
          _loading = false; 
        });
      }
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
            onRender: (pages) {
              setState(() { _totalPages = pages!; _isReady = true; });
              FirebaseCrashlytics.instance.log("📄 PDF Rendered: $pages pages");
            },
            onPageChanged: (page, total) => setState(() => _currentPage = page!),
            onError: (error) {
              FirebaseCrashlytics.instance.recordError(error, null, reason: 'PDFView Widget Error');
              setState(() => _error = error.toString());
            },
            onPageError: (page, error) {
              FirebaseCrashlytics.instance.log("⚠️ Error on page $page: $error");
            },
          ),

          // 2. العلامة المائية (طبقة متكررة)
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

  Widget _buildWatermarkRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildWatermarkItem(),
        _buildWatermarkItem(),
      ],
    );
  }

  // ✅ تصميم العلامة المائية (كما هو - بدون تغييرات التباين العالي)
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
