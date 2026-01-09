import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
  
  // بيانات المستخدم للعلامة المائية
  final String _userName = AppState().userData?['first_name'] ?? 'User';
  final String _userPhone = AppState().userData?['phone'] ?? ''; // تأكد من جلب الهاتف في Init API

  @override
  void initState() {
    super.initState();
    _loadPdf();
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
          responseType: ResponseType.bytes, // مهم جداً
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
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
    } catch (e) {
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
            swipeHorizontal: false, // التمرير العمودي أفضل للموبايل
            autoSpacing: false,
            pageFling: false,
            backgroundColor: AppColors.backgroundPrimary,
            onRender: (pages) => setState(() { _totalPages = pages!; _isReady = true; }),
            onViewCreated: (controller) {},
            onPageChanged: (page, total) => setState(() => _currentPage = page!),
            onError: (error) => setState(() => _error = error.toString()),
          ),

          // 2. العلامة المائية (Watermark Layer)
          // نستخدم IgnorePointer لكي لا تمنع اللمس عن الـ PDF
          IgnorePointer(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                children: [
                  // تكرار العلامة المائية في أماكن مختلفة
                  _buildWatermark(Alignment.topLeft),
                  _buildWatermark(Alignment.center),
                  _buildWatermark(Alignment.bottomRight),
                  
                  // علامة مائية عشوائية/متحركة (اختياري)
                  Positioned(
                    top: 200, left: 50,
                    child: Transform.rotate(
                      angle: -0.5,
                      child: Text(
                        "$_userName - $_userPhone",
                        style: TextStyle(
                          color: Colors.red.withOpacity(0.1), // لون خافت جداً
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
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

  Widget _buildWatermark(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Transform.rotate(
          angle: -0.2,
          child: Opacity(
            opacity: 0.08, // شفافية عالية لعدم إزعاج القراءة
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _userName.toUpperCase(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                Text(
                  _userPhone,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const Text(
                  "PRIVATE COPY",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
