import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/encryption_helper.dart';
import '../../core/services/local_pdf_server.dart'; // ✅ استدعاء السيرفر الجديد

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
  // المتغيرات الموحدة للعارض (سواء أونلاين أو أوفلاين)
  String? _viewerUrl;
  Map<String, String>? _viewerHeaders;
  
  // السيرفر المحلي للملفات الأوفلاين
  LocalPdfServer? _localServer;

  bool _loading = true;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  String _watermarkText = '';
  
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("📄 PDF Screen Opened: ${widget.title}");
    _initWatermarkText();
    _loadPdf();
  }

  @override
  void dispose() {
    // ✅ إيقاف السيرفر المحلي عند الخروج وتنظيف الموارد
    _localServer?.stop();
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

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
    });

    try {
      await EncryptionHelper.init(); // التأكد من جاهزية مفاتيح التشفير

      // 1. فحص الملفات الأوفلاين
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final String encryptedPath = downloadItem['path'];
        final File encryptedFile = File(encryptedPath);
        
        if (await encryptedFile.exists()) {
          // ✅ المنطق الموحد للأوفلاين: تشغيل السيرفر المحلي
          // يتم فك تشفير 32KB عند الطلب فقط
          _localServer = LocalPdfServer(encryptedPath, EncryptionHelper.key.base64);
          int port = await _localServer!.start();
          
          if (mounted) {
            setState(() {
              // رابط محلي يشير للسيرفر الخاص بنا
              _viewerUrl = 'http://127.0.0.1:$port/stream.pdf';
              _viewerHeaders = null; // لا نحتاج هيدرز محلياً
              _loading = false;
            });
          }
          return; // تم الانتهاء
        }
      }

      // 2. التحميل من الإنترنت (Online)
      // نستخدم العرض المباشر (Streaming) بدون تحميل مسبق
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      if (mounted) {
        setState(() {
          _viewerUrl = 'https://courses.aw478260.dpdns.org/api/secure/get-pdf?pdfId=${widget.pdfId}';
          _viewerHeaders = {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          };
          _loading = false;
        });
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF Load Failed');
      if (mounted) {
        setState(() { 
          _error = "Failed to load PDF."; 
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
        body: const Center(
          child: CircularPercentIndicator(
            radius: 30.0,
            lineWidth: 4.0,
            percent: 0.3, // مؤشر وهمي أثناء التجهيز
            animation: true,
            animateFromLastPercent: true,
            center: Icon(LucideIcons.loader2, color: Colors.white),
            progressColor: AppColors.accentYellow,
            backgroundColor: Colors.white10,
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
          // ✅ العارض الموحد (يستخدم Network دائماً)
          // في حالة الأوفلاين الرابط يكون Localhost
          // في حالة الأونلاين الرابط يكون API URL
          if (_viewerUrl != null)
            SfPdfViewer.network(
              _viewerUrl!,
              headers: _viewerHeaders,
              key: _pdfViewerKey,
              enableDoubleTapZooming: true, // تفعيل الزوم لجميع الأجهزة لأننا نستخدم الـ Streaming الخفيف
              pageLayoutMode: PdfPageLayoutMode.continuous,
              scrollDirection: PdfScrollDirection.vertical,
              canShowScrollHead: true,
              onDocumentLoaded: (details) {
                if (mounted) setState(() => _totalPages = details.document.pages.count);
              },
              onPageChanged: (details) {
                if (mounted) setState(() => _currentPage = details.newPageNumber - 1);
              },
              onDocumentLoadFailed: (args) {
                 if (mounted) setState(() => _error = "Failed to open document.");
              },
            ),

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

          // عداد الصفحات
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
