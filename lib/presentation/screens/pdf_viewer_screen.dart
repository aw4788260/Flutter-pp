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
  
  String _watermarkText = '';

  @override
  void initState() {
    super.initState();
    _initWatermarkText();
    _loadPdf();
  }

  void _initWatermarkText() {
    String phone = '';
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
    try {
      // 1. تحديد مسار التخزين الدائم (الكاش)
      final dir = await getApplicationDocumentsDirectory();
      // إنشاء مجلد خاص للكاش لتنظيمه
      final cacheDir = Directory('${dir.path}/cached_pdfs');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final file = File('${cacheDir.path}/${widget.pdfId}.pdf');
      bool useCachedFile = false;

      // 2. التحقق من وجود الملف وصلاحيته (10 أيام)
      if (await file.exists()) {
        final lastModified = await file.lastModified();
        final difference = DateTime.now().difference(lastModified);

        if (difference.inDays < 10) {
          useCachedFile = true; // الملف صالح، نستخدمه
        } else {
          // الملف قديم، سيتم تحميله وتحديثه
          await file.delete(); 
        }
      }

      if (useCachedFile) {
        // ✅ الفتح من الكاش
        if (mounted) {
          setState(() {
            _localPath = file.path;
            _loading = false;
          });
        }
      } else {
        // ⬇️ التحميل من السيرفر (غير موجود أو منتهي الصلاحية)
        await _downloadAndSavePdf(file);
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF Load Failed: ${widget.pdfId}');
      if (mounted) setState(() { _error = "Failed to load PDF. Check connection."; _loading = false; });
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

    // كتابة الملف (سيتم تحديث تاريخ التعديل تلقائياً)
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
          PDFView(
            filePath: _localPath,
            enableSwipe: true,
            swipeHorizontal: false,
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

          // العلامة المائية (رقم الهاتف فقط)
          IgnorePointer(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildWatermarkItem(),
                  _buildWatermarkItem(),
                  _buildWatermarkItem(),
                ],
              ),
            ),
          ),

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

  Widget _buildWatermarkItem() {
    return Transform.rotate(
      angle: -0.3,
      child: Center(
        child: Opacity(
          opacity: 0.15,
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
