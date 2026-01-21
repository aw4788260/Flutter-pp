import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; // مكتبة العرض
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/encryption_helper.dart';
import '../../core/services/file_crypto_service.dart'; // ✅ الخدمة الجديدة لفك التشفير
import '../../core/models/drawing_model.dart';

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
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // ✅ متغيرات جديدة لإدارة الملف المؤقت
  File? _decryptedTempFile; 
  String? _filePath; 
  Map<String, String>? _onlineHeaders; // لتخزين الهيدرز في حالة الأونلاين

  bool _loading = true;
  String? _error;
  bool _isOffline = false;
  String _watermarkText = '';

  // --- أدوات الرسم (كما هي) ---
  bool _isDrawingMode = false;
  int _selectedTool = 0; 
  Color _penColor = Colors.red;
  Color _highlightColor = Colors.yellow;
  double _penSize = 0.003; 
  double _highlightSize = 0.035; 
  double _eraserSize = 0.04; 

  Map<int, List<DrawingLine>> _pageDrawings = {};
  DrawingLine? _currentLine;
  int _activePage = 0; 
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _initWatermarkText();
    _preparePdf();
  }

  @override
  void dispose() {
    // ✅ حفظ الرسم قبل الخروج
    if (_isOffline) _saveDrawingsToHive();
    
    // ✅ تنظيف الملف المؤقت فور الخروج (أمان + توفير مساحة)
    if (_decryptedTempFile != null && _decryptedTempFile!.existsSync()) {
      try { _decryptedTempFile!.deleteSync(); } catch (_) {}
    }
    
    super.dispose();
  }

  Future<void> _saveDrawingsToHive() async {
    if (_pageDrawings.isEmpty) return;
    try {
      final box = await Hive.openBox('pdf_drawings_db');
      for (var entry in _pageDrawings.entries) {
        final page = entry.key;
        final lines = entry.value;
        if (lines.isNotEmpty) {
           final serialized = lines.map((l) => l.toJson()).toList();
           await box.put('${widget.pdfId}_$page', serialized);
        }
      }
    } catch (_) {}
  }

  Future<List<DrawingLine>> _getDrawingsForPage(int pageNumber) async {
    if (_pageDrawings.containsKey(pageNumber)) {
      return _pageDrawings[pageNumber]!;
    }
    try {
      final box = await Hive.openBox('pdf_drawings_db');
      final dynamic data = box.get('${widget.pdfId}_$pageNumber');
      List<DrawingLine> lines = [];
      if (data != null) {
        final List<dynamic> rawList = data;
        lines = rawList.map((e) => DrawingLine.fromJson(Map<String, dynamic>.from(e))).toList();
      }
      _pageDrawings[pageNumber] = lines;
      return lines;
    } catch (_) {
      return [];
    }
  }

  void _initWatermarkText() {
    String displayText = '';
    if (AppState().userData != null) displayText = AppState().userData!['phone'] ?? '';
    setState(() => _watermarkText = displayText.isNotEmpty ? displayText : 'User');
  }

  // ✅ الدالة الأساسية المعدلة
  Future<void> _preparePdf() async {
    setState(() => _loading = true);
    try {
      // التأكد من تهيئة مفاتيح التشفير
      await EncryptionHelper.init(); 
      await FileCryptoService.init();

      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      String? offlinePath;
      bool fileExistsLocally = false;

      // 1. التحقق من وجود الملف في بيانات التحميل
      if (downloadItem != null && downloadItem['path'] != null) {
        offlinePath = downloadItem['path'];
        // 2. التحقق من وجود الملف فعلياً على القرص
        if (await File(offlinePath!).exists()) {
          fileExistsLocally = true;
        }
      }

      if (fileExistsLocally) {
        // 🟢 المسار الأول: أوفلاين (فك تشفير لملف مؤقت)
        setState(() => _isOffline = true);
        
        // فك التشفير باستخدام ChaCha20
        _decryptedTempFile = await FileCryptoService.decryptToTempFile(offlinePath!);
        
        if (mounted) {
          setState(() {
            _filePath = _decryptedTempFile!.path; // مسار الملف المحلي الصريح
            _loading = false;
          });
        }
      } else {
        // 🟠 المسار الثاني: أونلاين (عرض مباشر من الرابط مع Headers)
        setState(() => _isOffline = false);
        
        var box = await Hive.openBox('auth_box');
        final headers = {
          'x-user-id': box.get('user_id')?.toString() ?? '',
          'x-device-id': box.get('device_id')?.toString() ?? '',
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        };
        
        final url = 'https://courses.aw478260.dpdns.org/api/secure/get-pdf?pdfId=${widget.pdfId}';
        
        if (mounted) {
          setState(() {
            _filePath = url;
            _onlineHeaders = headers; // حفظ الهيدرز لاستخدامها في العرض
            _loading = false;
          });
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: "PDF Open Error");
      if (mounted) setState(() { _error = "Failed to load PDF."; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_error != null) return Scaffold(backgroundColor: AppColors.backgroundPrimary, appBar: AppBar(backgroundColor: Colors.transparent, leading: const BackButton(color: Colors.white)), body: Center(child: Text(_error!, style: const TextStyle(color: Colors.white))));

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundPrimary,
      
      endDrawer: Drawer(
        backgroundColor: AppColors.backgroundSecondary,
        width: 250,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 40, 16, 16),
              child: Text("PAGE INDEX", style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: _totalPages == 0 
                ? const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)) 
                : ListView.builder(
                    itemCount: _totalPages,
                    itemBuilder: (context, index) {
                      final pageNum = index + 1;
                      final isCurrent = _pdfController.pageNumber == pageNum;
                      return ListTile(
                        title: Text("Page $pageNum", style: TextStyle(color: isCurrent ? AppColors.accentYellow : Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                        leading: Icon(LucideIcons.fileText, color: isCurrent ? AppColors.accentYellow : Colors.white54, size: 18),
                        onTap: () {
                          _pdfController.goToPage(pageNumber: pageNum);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
            ),
          ],
        ),
      ),

      appBar: AppBar(
        title: Row(
          children: [
            Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 14, color: Colors.white), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isOffline ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isOffline ? Colors.green : Colors.blue, width: 1),
              ),
              child: Row(
                children: [
                  Icon(_isOffline ? LucideIcons.hardDrive : LucideIcons.cloud, size: 12, color: _isOffline ? Colors.green : Colors.blue),
                  const SizedBox(width: 4),
                  Text(_isOffline ? "Offline" : "Stream", style: TextStyle(fontSize: 10, color: _isOffline ? Colors.green : Colors.blue, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.backgroundSecondary,
        leading: BackButton(
          color: AppColors.accentYellow,
          onPressed: () async {
             // حفظ عند الرجوع إذا كان أوفلاين
             if(_isOffline) await _saveDrawingsToHive();
             if(context.mounted) Navigator.pop(context);
          }
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.list, color: AppColors.accentYellow),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          if (_isOffline)
            IconButton(
              icon: Icon(
                _isDrawingMode ? LucideIcons.checkCircle : LucideIcons.penTool, 
                color: _isDrawingMode ? Colors.greenAccent : Colors.white
              ),
              onPressed: () => setState(() => _isDrawingMode = !_isDrawingMode),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ العرض: نستخدم PdfViewer.file للأوفلاين و PdfViewer.uri للأونلاين (مع الهيدرز)
          _isOffline 
          ? PdfViewer.file(
              _filePath!,
              controller: _pdfController,
              params: _buildPdfParams(),
            )
          : PdfViewer.uri(
              Uri.parse(_filePath!),
              httpHeaders: _onlineHeaders, // تمرير الهيدرز هنا
              controller: _pdfController,
              preferRangeAccess: true, // تفعيل طلبات النطاق للأونلاين
              params: _buildPdfParams(),
            ),

          // 2. العلامة المائية
          IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: 0.35, 
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    3, 
                    (index) => Transform.rotate(
                      angle: -0.5, 
                      child: Text(
                        _watermarkText, 
                        textScaler: const TextScaler.linear(2.2),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold, 
                          color: Colors.grey, 
                          decoration: TextDecoration.none
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_isDrawingMode && _isOffline)
            Positioned(
              bottom: 40, left: 20, right: 20,
              child: _buildToolbar(),
            ),
        ],
      ),
    );
  }

  // ✅ فصل إعدادات الـ PDF لتقليل التكرار
  PdfViewerParams _buildPdfParams() {
    return PdfViewerParams(
      backgroundColor: AppColors.backgroundPrimary,
      textSelectionParams: const PdfTextSelectionParams(enabled: false), 
      scrollPhysics: const BouncingScrollPhysics(),
      
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: const CircularProgressIndicator(color: AppColors.accentYellow),
          ),
        );
      },
      
      onDocumentChanged: (document) {
        if (mounted) setState(() => _totalPages = document?.pages.length ?? 0);
      },

      pageOverlaysBuilder: (context, pageRect, page) {
        if (!_isOffline) return [];
        return [
          Positioned.fill(
            child: FutureBuilder<List<DrawingLine>>(
              future: _getDrawingsForPage(page.pageNumber),
              builder: (context, snapshot) {
                final lines = snapshot.data ?? [];
                final allLines = [...lines];
                if (_isDrawingMode && _currentLine != null && _activePage == page.pageNumber) {
                  allLines.add(_currentLine!);
                }
                return IgnorePointer(
                  ignoring: !_isDrawingMode,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      if (!_isDrawingMode) return;
                      final renderBox = context.findRenderObject() as RenderBox;
                      final localPos = renderBox.globalToLocal(details.globalPosition);
                      final relativePoint = Offset(
                        localPos.dx / pageRect.width,
                        localPos.dy / pageRect.height,
                      );
                      setState(() {
                        _activePage = page.pageNumber;
                        double width = _penSize;
                        int color = _penColor.value;
                        bool isHighlighter = false;
                        bool isEraser = false;

                        if (_selectedTool == 1) { 
                          width = _highlightSize;
                          color = _highlightColor.value;
                          isHighlighter = true;
                        } else if (_selectedTool == 2) { 
                          width = _eraserSize;
                          color = 0; 
                          isEraser = true;
                        }

                        _currentLine = DrawingLine(
                          points: [relativePoint],
                          color: color,
                          strokeWidth: width,
                          isHighlighter: isHighlighter,
                          isEraser: isEraser,
                        );
                      });
                    },
                    onPanUpdate: (details) {
                      if (!_isDrawingMode || _currentLine == null) return;
                      final renderBox = context.findRenderObject() as RenderBox;
                      final localPos = renderBox.globalToLocal(details.globalPosition);
                      final relativePoint = Offset(
                        localPos.dx / pageRect.width,
                        localPos.dy / pageRect.height,
                      );
                      setState(() {
                        _currentLine!.points.add(relativePoint);
                      });
                    },
                    onPanEnd: (details) {
                      if (_currentLine != null) {
                        setState(() {
                          if (_pageDrawings[page.pageNumber] == null) _pageDrawings[page.pageNumber] = [];
                          _pageDrawings[page.pageNumber]!.add(_currentLine!);
                          _currentLine = null;
                        });
                      }
                    },
                    child: CustomPaint(
                      painter: RelativeSketchPainter(
                        lines: allLines,
                        pageSize: pageRect.size,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ];
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildToolButton(LucideIcons.penTool, 0),
              _buildToolButton(LucideIcons.highlighter, 1),
              _buildToolButton(LucideIcons.eraser, 2), 
              
              IconButton(
                icon: const Icon(LucideIcons.undo, color: Colors.white),
                onPressed: () {
                   if (_pageDrawings[_activePage]?.isNotEmpty ?? false) {
                     setState(() {
                       _pageDrawings[_activePage]!.removeLast();
                     });
                   }
                },
              ),

              Container(width: 1, height: 24, color: Colors.grey),
              
              if (_selectedTool != 2) ...[
                _buildColorButton(Colors.black),
                _buildColorButton(Colors.red),
                _buildColorButton(Colors.blue),
                _buildColorButton(Colors.yellow, isHighlight: true),
                _buildColorButton(Colors.green, isHighlight: true),
              ] else 
                const Text("Eraser Active", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            children: [
              const Icon(LucideIcons.circle, size: 8, color: Colors.white70),
              Expanded(
                child: Slider(
                  value: _getCurrentSize(),
                  min: 0.001,
                  max: 0.08, 
                  activeColor: _selectedTool == 2 ? Colors.white : (_selectedTool == 1 ? _highlightColor : _penColor),
                  inactiveColor: Colors.grey,
                  onChanged: (val) {
                    setState(() {
                      if (_selectedTool == 2) _eraserSize = val;
                      else if (_selectedTool == 1) _highlightSize = val;
                      else _penSize = val;
                    });
                  },
                ),
              ),
              const Icon(LucideIcons.circle, size: 18, color: Colors.white70),
            ],
          ),
        ],
      ),
    );
  }

  double _getCurrentSize() {
    if (_selectedTool == 2) return _eraserSize;
    if (_selectedTool == 1) return _highlightSize;
    return _penSize;
  }

  Widget _buildToolButton(IconData icon, int toolIndex) {
    final bool isSelected = _selectedTool == toolIndex;
    return IconButton(
      icon: Icon(icon, color: isSelected ? AppColors.accentYellow : Colors.grey),
      onPressed: () => setState(() => _selectedTool = toolIndex),
    );
  }

  Widget _buildColorButton(Color color, {bool isHighlight = false}) {
    final bool isSelected = _selectedTool == 1 ? _highlightColor == color : _penColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isHighlight) {
             _highlightColor = color;
             _selectedTool = 1;
          } else { 
             _penColor = color;
             _selectedTool = 0;
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 26, height: 26,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null),
      ),
    );
  }
}

class RelativeSketchPainter extends CustomPainter {
  final List<DrawingLine> lines;
  final Size pageSize;

  RelativeSketchPainter({required this.lines, required this.pageSize});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (var line in lines) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = line.isHighlighter ? StrokeCap.butt : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = line.strokeWidth * pageSize.width;

      if (line.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = Colors.transparent; 
      } else {
        paint.color = Color(line.color).withOpacity(line.isHighlighter ? 0.35 : 1.0);
        if (line.isHighlighter) paint.blendMode = BlendMode.darken; 
      }

      if (line.points.length > 1) {
        final path = Path();
        var start = Offset(line.points[0].dx * pageSize.width, line.points[0].dy * pageSize.height);
        path.moveTo(start.dx, start.dy);

        for (int i = 1; i < line.points.length; i++) {
          var p = Offset(line.points[i].dx * pageSize.width, line.points[i].dy * pageSize.height);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      } else if (line.points.isNotEmpty) {
        var p = Offset(line.points[0].dx * pageSize.width, line.points[0].dy * pageSize.height);
        canvas.drawPoints(PointMode.points, [p], paint);
      }
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
