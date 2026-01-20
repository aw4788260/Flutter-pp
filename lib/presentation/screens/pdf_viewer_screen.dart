import 'dart:io';
import 'dart:async';
import 'dart:ui'; // ضروري للرسم
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
  // --- متغيرات النظام ---
  String? _viewerUrl;
  LocalPdfServer? _localServer;
  bool _loading = true;
  String? _error;
  String _watermarkText = '';
  
  // --- متغيرات الـ PDF ---
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  int _totalPages = 0;
  int _currentPage = 1; 
  bool _isOffline = false; 

  // --- 🎨 متغيرات الرسم (Drawing Engine) ---
  bool _isDrawingMode = false; // تفعيل وضع الرسم
  bool _isHighlighter = false; // هل الأداة الحالية هايلايت؟
  
  // الألوان المختارة
  Color _penColor = Colors.red;
  Color _highlightColor = Colors.yellow;
  
  // الأحجام المختارة
  double _penSize = 3.0;
  double _highlightSize = 25.0;

  // تخزين الرسومات: Map<رقم الصفحة, قائمة الخطوط>
  Map<int, List<DrawingLine>> _pageDrawings = {};
  
  // الخط الحالي الذي يتم رسمه الآن
  DrawingLine? _currentLine;

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
    _log("Closing Screen");
    if (_isOffline) _saveDrawingsToHive();
    _localServer?.stop();
    super.dispose();
  }

  // 💾 --- منطق حفظ واسترجاع الرسومات (Hive) ---
  Future<void> _saveDrawingsToHive() async {
    try {
      final box = await Hive.openBox('pdf_drawings_db');
      _pageDrawings.forEach((page, lines) {
        final List<Map<String, dynamic>> serializedLines = lines.map((line) => line.toJson()).toList();
        box.put('${widget.pdfId}_$page', serializedLines);
      });
      _log("✅ Drawings saved successfully.");
    } catch (e) {
      _log("❌ Error saving drawings: $e");
    }
  }

  Future<void> _loadDrawingsForPage(int pageNum) async {
    try {
      final box = await Hive.openBox('pdf_drawings_db');
      final dynamic data = box.get('${widget.pdfId}_$pageNum');
      
      if (data != null) {
        final List<dynamic> rawList = data;
        final List<DrawingLine> loadedLines = rawList.map((e) => DrawingLine.fromJson(Map<String, dynamic>.from(e))).toList();
        
        setState(() {
          _pageDrawings[pageNum] = loadedLines;
        });
      } else {
        setState(() {
          _pageDrawings[pageNum] = [];
        });
      }
    } catch (e) {
      _log("⚠️ Error loading page $pageNum drawings: $e");
    }
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

      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);
      
      String? offlinePath;

      if (downloadItem != null && downloadItem['path'] != null) {
        offlinePath = downloadItem['path'];
        if (await File(offlinePath!).exists()) {
          _isOffline = true;
        }
      }

      _log(_isOffline ? "📂 Mode: OFFLINE (Drawing Enabled)" : "🌐 Mode: ONLINE (View Only)");

      if (_isOffline) await _loadDrawingsForPage(1);

      _localServer?.stop();

      if (_isOffline) {
         // ✅ أوفلاين: فك التشفير
         _localServer = LocalPdfServer.offline(offlinePath, EncryptionHelper.key.base64);
      } else {
         // ✅ أونلاين: بروكسي لحماية الهيدرز
         var box = await Hive.openBox('auth_box');
         final userId = box.get('user_id');
         final deviceId = box.get('device_id');
         
         final Map<String, String> headers = {
            'x-user-id': userId?.toString() ?? '',
            'x-device-id': deviceId?.toString() ?? '',
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
         };
         
         final url = 'https://courses.aw478260.dpdns.org/api/secure/get-pdf?pdfId=${widget.pdfId}&t=${DateTime.now().millisecondsSinceEpoch}';
         
         _localServer = LocalPdfServer.online(url, headers);
      }

      int port = await _localServer!.start();
      final localhostUrl = 'http://127.0.0.1:$port/stream.pdf';
      
      _log("🚀 Server Ready: $localhostUrl");

      if (mounted) {
        setState(() {
          _viewerUrl = localhostUrl;
          _loading = false;
        });
      }

    } catch (e, stack) {
      _log("❌ FATAL ERROR: $e");
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF Load Failed');
      if (mounted) {
        setState(() { _error = "Failed to load PDF."; _loading = false; });
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
          onPressed: () async {
            if (_isOffline) await _saveDrawingsToHive();
            if (context.mounted) Navigator.pop(context);
          }
        ),
        actions: [
          // 🖍️ زر تفعيل وضع الرسم (أوفلاين فقط)
          if (_isOffline)
            IconButton(
              icon: Icon(
                _isDrawingMode ? LucideIcons.checkCircle : LucideIcons.penTool,
                color: _isDrawingMode ? Colors.greenAccent : Colors.white
              ),
              onPressed: () {
                setState(() => _isDrawingMode = !_isDrawingMode);
              },
            ),
          
          IconButton(
            icon: const Icon(LucideIcons.search, color: Colors.white),
            onPressed: () { _pdfViewerKey.currentState?.openBookmarkView(); },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. PDF Viewer Layer
          SfPdfViewer.network(
            _viewerUrl!,
            key: _pdfViewerKey,
            enableTextSelection: false, // ⛔️ منع النسخ
            // السماح بالتمرير دائماً (لأننا نستخدم IgnorePointer للتحكم)
            interactionMode: PdfInteractionMode.pan, 
            enableDoubleTapZooming: !_isDrawingMode, 
            
            onDocumentLoaded: (details) {
              if (mounted) setState(() => _totalPages = details.document.pages.count);
            },
            onPageChanged: (details) {
              if (_isOffline) {
                 setState(() {
                   _currentPage = details.newPageNumber;
                 });
                 _loadDrawingsForPage(_currentPage);
              } else {
                 if (mounted) setState(() => _currentPage = details.newPageNumber);
              }
            },
            onDocumentLoadFailed: (args) {
               if (mounted) setState(() => _error = "Failed to open document.");
            },
          ),

          // 2. Watermark Layer
          IgnorePointer(
            child: Container(
              width: double.infinity, height: double.infinity, color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [ _buildWatermarkRow(), _buildWatermarkRow(), _buildWatermarkRow(), _buildWatermarkRow() ],
              ),
            ),
          ),

          // 3. Drawing Layer (Offline only)
          if (_isOffline)
            Positioned.fill(
              // ✅ استخدام IgnorePointer للسماح بالتمرير عند إغلاق الأقلام
              child: IgnorePointer(
                ignoring: !_isDrawingMode,
                child: GestureDetector(
                  onPanStart: (details) {
                     setState(() {
                       _currentLine = DrawingLine(
                         points: [details.localPosition],
                         color: _isHighlighter ? _highlightColor.value : _penColor.value,
                         strokeWidth: _isHighlighter ? _highlightSize : _penSize,
                         isHighlighter: _isHighlighter,
                       );
                     });
                  },
                  onPanUpdate: (details) {
                     setState(() {
                       _currentLine?.points.add(details.localPosition);
                     });
                  },
                  onPanEnd: (details) {
                     setState(() {
                       if (_currentLine != null) {
                         if (_pageDrawings[_currentPage] == null) {
                           _pageDrawings[_currentPage] = [];
                         }
                         _pageDrawings[_currentPage]!.add(_currentLine!);
                         _currentLine = null;
                       }
                     });
                  },
                  child: CustomPaint(
                    painter: SketchPainter(
                      lines: _pageDrawings[_currentPage] ?? [],
                      currentLine: _currentLine,
                    ),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),

          // 4. Drawing Toolbar
          if (_isDrawingMode && _isOffline)
            Positioned(
              bottom: 60, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // أدوات الرسم
                        _buildToolButton(LucideIcons.penTool, false),
                        _buildToolButton(LucideIcons.highlighter, true),
                        
                        const SizedBox(width: 8),
                        
                        // ✅ زر التراجع (Undo) بجوار الأقلام
                        IconButton(
                          icon: const Icon(LucideIcons.undo, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              if (_pageDrawings[_currentPage]?.isNotEmpty ?? false) {
                                _pageDrawings[_currentPage]!.removeLast();
                              }
                            });
                          },
                        ),

                        const SizedBox(width: 8),
                        Container(width: 1, height: 24, color: Colors.grey),
                        const SizedBox(width: 8),
                        
                        // الألوان (باستخدام Expanded لتوزيع المساحة)
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildColorButton(Colors.black),
                                _buildColorButton(Colors.red),
                                _buildColorButton(Colors.blue),
                                _buildColorButton(Colors.yellow, isHighlight: true),
                                _buildColorButton(Colors.green, isHighlight: true),
                                _buildColorButton(Colors.pinkAccent, isHighlight: true),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // التحكم في الحجم (Slider)
                    Row(
                      children: [
                        const Icon(LucideIcons.circle, size: 10, color: Colors.white70),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: _isHighlighter ? _highlightColor : _penColor,
                              thumbColor: Colors.white,
                              trackHeight: 2.0,
                            ),
                            child: Slider(
                              value: _isHighlighter ? _highlightSize : _penSize,
                              min: _isHighlighter ? 10.0 : 1.0,
                              max: _isHighlighter ? 50.0 : 15.0,
                              onChanged: (val) {
                                setState(() {
                                  if (_isHighlighter) {
                                    _highlightSize = val;
                                  } else {
                                    _penSize = val;
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        const Icon(LucideIcons.circle, size: 20, color: Colors.white70),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // 5. Page Counter
          Positioned(
            bottom: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Text(
                _totalPages > 0 ? "${_currentPage} / $_totalPages" : "${_currentPage}",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(IconData icon, bool isHighlightTool) {
    final bool isSelected = _isHighlighter == isHighlightTool;
    return Container(
      decoration: isSelected ? BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)) : null,
      child: IconButton(
        icon: Icon(icon, color: isSelected ? AppColors.accentYellow : Colors.grey),
        onPressed: () => setState(() => _isHighlighter = isHighlightTool),
      ),
    );
  }

  Widget _buildColorButton(Color color, {bool isHighlight = false}) {
    final bool isSelected = _isHighlighter ? _highlightColor == color : _penColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_isHighlighter) { _highlightColor = color; } else { _penColor = color; }
          // تبديل الأداة تلقائياً بناءً على نوع اللون المختار
          if (isHighlight) _isHighlighter = true;
          if (!isHighlight && (color == Colors.black || color == Colors.red || color == Colors.blue)) _isHighlighter = false;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
        ),
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

// =========================================================
// 🖍️ Drawing Models & Painter
// =========================================================

class DrawingLine {
  final List<Offset> points;
  final int color;
  final double strokeWidth;
  final bool isHighlighter;

  DrawingLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isHighlighter,
  });

  Map<String, dynamic> toJson() {
    return {
      'c': color,
      'w': strokeWidth,
      'h': isHighlighter,
      'p': points.map((e) => {'x': e.dx, 'y': e.dy}).toList(),
    };
  }

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    var pts = (json['p'] as List).map((e) => Offset(e['x'], e['y'])).toList();
    return DrawingLine(
      points: pts,
      color: json['c'],
      strokeWidth: json['w'],
      isHighlighter: json['h'] ?? false,
    );
  }
}

class SketchPainter extends CustomPainter {
  final List<DrawingLine> lines;
  final DrawingLine? currentLine;

  SketchPainter({required this.lines, this.currentLine});

  @override
  void paint(Canvas canvas, Size size) {
    for (var line in lines) {
      _paintLine(canvas, line);
    }
    if (currentLine != null) {
      _paintLine(canvas, currentLine!);
    }
  }

  void _paintLine(Canvas canvas, DrawingLine line) {
    final paint = Paint()
      ..color = Color(line.color).withOpacity(line.isHighlighter ? 0.35 : 1.0)
      ..strokeWidth = line.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = line.isHighlighter ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (line.isHighlighter) {
      paint.blendMode = BlendMode.srcOver; 
    }

    if (line.points.length > 1) {
      final path = Path();
      path.moveTo(line.points[0].dx, line.points[0].dy);
      for (int i = 1; i < line.points.length; i++) {
        path.lineTo(line.points[i].dx, line.points[i].dy);
      }
      canvas.drawPath(path, paint);
    } else if (line.points.length == 1) {
      canvas.drawPoints(PointMode.points, line.points, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
