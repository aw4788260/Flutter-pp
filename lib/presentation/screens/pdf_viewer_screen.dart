import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ استيراد Crashlytics
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfId;
  final String title;

  const PdfViewerScreen({super.key, required this.pdfId, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  bool _loading = true;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  
  // نص العلامة المائية
  String _watermarkText = 'User ID';

  @override
  void initState() {
    super.initState();
    _loadPdf();
    _initWatermarkText();
  }

  // تهيئة نص العلامة المائية فقط (بدون حركة)
  void _initWatermarkText() {
    if (AppState().userData != null) {
      final user = AppState().userData!;
      _watermarkText = "${user['username'] ?? 'User'} - ${user['phone'] ?? ''}";
    } else {
       try {
         if(Hive.isBoxOpen('auth_box')) {
           var box = Hive.box('auth_box');
           _watermarkText = "${box.get('username') ?? 'User'} - ${box.get('phone') ?? ''}";
         }
       } catch(_) {}
    }
  }

  Future<void> _loadPdf() async {
    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      // 1. طلب الملف من الـ API
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

      // 2. حفظ الملف مؤقتاً
      final bytes = response.data as Uint8List;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.pdfId}.pdf');
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        setState(() {
          _localPath = file.path;
          _loading = false;
        });
      }
    } catch (e, stack) {
      // ✅ تسجيل خطأ التحميل
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF Download Failed: ${widget.pdfId}');
      if (mounted) setState(() { _error = "Failed to load PDF. Check connection."; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_error != null) return Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))));

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        leading: IconButton(icon: const Icon(LucideIcons.arrowLeft), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          // 1. عارض الـ PDF
          PDFView(
            filePath: _localPath,
            enableSwipe: true,
            swipeHorizontal: false, // التمرير العمودي
            autoSpacing: false,
            pageFling: false,
            backgroundColor: AppColors.backgroundPrimary,
            onRender: (pages) => setState(() { _totalPages = pages!; _isReady = true; }),
            onViewCreated: (controller) {},
            onPageChanged: (page, total) => setState(() => _currentPage = page!),
            onError: (error) {
              FirebaseCrashlytics.instance.recordError(error, null, reason: 'PDF Render Error');
              setState(() => _error = error.toString());
            },
            onPageError: (page, error) {
              FirebaseCrashlytics.instance.recordError(error, null, reason: 'PDF Page $page Error');
            },
          ),

          // 2. العلامة المائية الثابتة (3 مرات فقط)
          IgnorePointer(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly, // توزيع المسافات بالتساوي
                children: [
                  _buildWatermarkItem(),
                  _buildWatermarkItem(),
                  _buildWatermarkItem(),
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
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // عنصر العلامة المائية الواحد
  Widget _buildWatermarkItem() {
    return Transform.rotate(
      angle: -0.3, // ميلان النص
      child: Center(
        child: Opacity(
          opacity: 0.15, // شفافية خفيفة
          child: Text(
            _watermarkText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
