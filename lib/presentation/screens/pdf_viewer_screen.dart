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
  // المتغيرات الموحدة للعارض
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

  // 🔍 دالة تسجيل موحدة (Logs)
  void _log(String message) {
    final msg = "🔍 [PDF_SCREEN] $message";
    print(msg); // يظهر في Run Console
    try {
      FirebaseCrashlytics.instance.log(msg); // يرسل لـ Firebase
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _log("Opened Screen for: ${widget.title}");
    _initWatermarkText();
    _loadPdf();
  }

  @override
  void dispose() {
    _log("Closing Screen - Stopping Local Server if running");
    // ✅ إيقاف السيرفر المحلي عند الخروج
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
      await EncryptionHelper.init(); 

      // 1. فحص الملفات الأوفلاين
      _log("Checking offline database for PDF ID: ${widget.pdfId}");
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final String encryptedPath = downloadItem['path'];
        final File encryptedFile = File(encryptedPath);
        
        _log("Found offline entry. Path: $encryptedPath");

        if (await encryptedFile.exists()) {
          _log("✅ File exists on disk. Starting Local Proxy Server...");
          
          try {
            // ✅ المنطق الموحد: تشغيل السيرفر المحلي المعزول
            _localServer = LocalPdfServer(encryptedPath, EncryptionHelper.key.base64);
            int port = await _localServer!.start();
            
            final localhostUrl = 'http://127.0.0.1:$port/stream.pdf';
            _log("🚀 Proxy Started Successfully. URL: $localhostUrl");

            if (mounted) {
              setState(() {
                _viewerUrl = localhostUrl;
                _viewerHeaders = null; // لا نحتاج headers مع السيرفر المحلي
                _loading = false;
              });
            }
            return; 
          } catch (serverError, stack) {
             _log("❌ Failed to start Local Server: $serverError");
             FirebaseCrashlytics.instance.recordError(serverError, stack, reason: 'Local Server Start Failed');
             // لا نوقف التنفيذ، سنحاول الأونلاين كبديل
          }
        } else {
          _log("⚠️ File path is in DB but file is MISSING on disk!");
        }
      } else {
        _log("No offline download found. Switching to Online Mode.");
      }

      // 2. التحميل من الإنترنت (Online)
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      _log("Preparing Online Stream...");

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
        _log("✅ Online Stream URL set.");
      }

    } catch (e, stack) {
      _log("❌ FATAL ERROR in _loadPdf: $e");
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
        // ✅ تم الإصلاح: حذفنا const من هنا لأن الودجت يحتوي على أنيميشن
        body: Center(
          child: CircularPercentIndicator(
            radius: 30.0,
            lineWidth: 4.0,
            percent: 0.3,
            animation: true,
            animateFromLastPercent: true,
            center: const Icon(LucideIcons.loader2, color: Colors.white),
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
          if (_viewerUrl != null)
            SfPdfViewer.network(
              _viewerUrl!,
              headers: _viewerHeaders,
              key: _pdfViewerKey,
              enableDoubleTapZooming: true,
              pageLayoutMode: PdfPageLayoutMode.continuous,
              scrollDirection: PdfScrollDirection.vertical,
              canShowScrollHead: true,
              onDocumentLoaded: (details) {
                _log("✅ PDF Document Loaded. Pages: ${details.document.pages.count}");
                if (mounted) setState(() => _totalPages = details.document.pages.count);
              },
              onPageChanged: (details) {
                if (mounted) setState(() => _currentPage = details.newPageNumber - 1);
              },
              onDocumentLoadFailed: (args) {
                 _log("❌ PDF Viewer Failed: ${args.error} - ${args.description}");
                 if (mounted) setState(() => _error = "Failed to open document.");
              },
            ),

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
