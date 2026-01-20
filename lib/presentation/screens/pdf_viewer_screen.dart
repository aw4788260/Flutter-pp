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
import '../../core/services/local_pdf_server.dart';

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
  // الرابط المحلي (Localhost) دائماً
  String? _viewerUrl;
  
  // السيرفر المحلي (يعمل كـ Decryptor أو Proxy)
  LocalPdfServer? _localServer;

  bool _loading = true;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  String _watermarkText = '';
  
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  void _log(String message) {
    final msg = "🔍 [PDF_SCREEN] $message";
    print(msg);
    try { FirebaseCrashlytics.instance.log(msg); } catch (_) {}
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
    _log("Closing Screen - Stopping Local Server");
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
    setState(() => _loading = true);

    try {
      await EncryptionHelper.init(); 

      // 1. تحديد ما إذا كان الملف أوفلاين أم أونلاين
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);
      
      bool isOffline = false;
      String? offlinePath;

      if (downloadItem != null && downloadItem['path'] != null) {
        offlinePath = downloadItem['path'];
        if (await File(offlinePath!).exists()) {
          isOffline = true;
        }
      }

      _log(isOffline ? "📂 Mode: OFFLINE" : "🌐 Mode: ONLINE");

      // إيقاف أي سيرفر سابق
      _localServer?.stop();

      if (isOffline) {
         // ✅ إعداد السيرفر للأوفلاين (فك التشفير)
         _localServer = LocalPdfServer.offline(offlinePath, EncryptionHelper.key.base64);
      } else {
         // ✅ إعداد السيرفر للأونلاين (بروكسي ونفق)
         var box = await Hive.openBox('auth_box');
         final userId = box.get('user_id');
         final deviceId = box.get('device_id');
         
         final headers = {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
         };
         
         // إضافة timestamp لمنع الكاش القديم في التطبيق
         final url = 'https://courses.aw478260.dpdns.org/api/secure/get-pdf?pdfId=${widget.pdfId}&t=${DateTime.now().millisecondsSinceEpoch}';
         
         _localServer = LocalPdfServer.online(url, headers);
      }

      // تشغيل السيرفر والحصول على البورت
      int port = await _localServer!.start();
      final localhostUrl = 'http://127.0.0.1:$port/stream.pdf';
      
      _log("🚀 Server Started on port $port. URL: $localhostUrl");

      if (mounted) {
        setState(() {
          _viewerUrl = localhostUrl; // المشغل يتصل دائماً بـ Localhost
          _loading = false;
        });
      }

    } catch (e, stack) {
      _log("❌ FATAL LOAD ERROR: $e");
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
        body: Center(
          child: CircularPercentIndicator(
            radius: 30.0, lineWidth: 4.0, percent: 0.3, animation: true,
            center: const Icon(LucideIcons.loader2, color: Colors.white),
            progressColor: AppColors.accentYellow, backgroundColor: Colors.white10,
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
            onPressed: () { _pdfViewerKey.currentState?.openBookmarkView(); },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_viewerUrl != null)
            SfPdfViewer.network(
              _viewerUrl!,
              // ⚠️ لا نمرر Headers هنا، السيرفر المحلي يتولى الأمر
              key: _pdfViewerKey,
              enableDoubleTapZooming: true,
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
                 _log("❌ PDF Viewer Failed: ${args.description}");
                 if (mounted) setState(() => _error = "Failed to open document.");
              },
            ),

          IgnorePointer(
            child: Container(
              width: double.infinity, height: double.infinity, color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [ _buildWatermarkRow(), _buildWatermarkRow(), _buildWatermarkRow(), _buildWatermarkRow() ],
              ),
            ),
          ),

          Positioned(
            bottom: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
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
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildWatermarkItem(), _buildWatermarkItem()]);
  }

  Widget _buildWatermarkItem() {
    return Transform.rotate(
      angle: -0.5, 
      child: Opacity(
        opacity: 0.15,
        child: Text(_watermarkText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.grey, decoration: TextDecoration.none)),
      ),
    );
  }
}
