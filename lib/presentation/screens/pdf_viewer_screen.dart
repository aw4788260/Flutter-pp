import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; // ✅ المكتبة القوية
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/encryption_helper.dart';
import '../../core/services/local_pdf_server.dart';
// تأكد من وجود ملف الموديل الذي أنشأناه سابقاً
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
  // --- النظام ---
  final PdfViewerController _pdfController = PdfViewerController();
  LocalPdfServer? _localServer;
  String? _filePath; 
  bool _loading = true;
  String? _error;
  bool _isOffline = false;
  
  // --- الرسم ---
  bool _isDrawingMode = false;
  bool _isHighlighter = false;
  Color _penColor = Colors.red;
  Color _highlightColor = Colors.yellow;
  double _penSize = 0.003; // حجم نسبي (صغير للقلم)
  double _highlightSize = 0.035; // حجم نسبي (كبير للهايلايت)

  // تخزين الرسومات: Map<رقم الصفحة, قائمة الخطوط>
  Map<int, List<DrawingLine>> _pageDrawings = {};
  DrawingLine? _currentLine;
  int _activePage = 0; // الصفحة التي يلمسها المستخدم حالياً

  // 🛡️ دالة تسجيل أخطاء مركزية ومكثفة
  void _logError(String context, Object error, [StackTrace? stack]) {
    final msg = "🔴 [PDF_ERROR][$context] $error";
    debugPrint(msg);
    
    // تسجيل سياق إضافي للمساعدة في الحل
    FirebaseCrashlytics.instance.setCustomKey('pdf_id', widget.pdfId);
    FirebaseCrashlytics.instance.setCustomKey('pdf_title', widget.title);
    FirebaseCrashlytics.instance.setCustomKey('is_offline', _isOffline);
    FirebaseCrashlytics.instance.setCustomKey('error_context', context);
    
    FirebaseCrashlytics.instance.recordError(error, stack, reason: msg, fatal: false);
  }

  void _logInfo(String message) {
    debugPrint("🟢 [PDF_INFO] $message");
    FirebaseCrashlytics.instance.log(message);
  }

  @override
  void initState() {
    super.initState();
    _identifyUser();
    _preparePdf();
  }

  void _identifyUser() {
    try {
      final userData = AppState().userData;
      if (userData != null) {
        FirebaseCrashlytics.instance.setUserIdentifier(userData['id']?.toString() ?? 'anon');
        FirebaseCrashlytics.instance.setCustomKey('user_phone', userData['phone'] ?? '');
      }
    } catch (e) {
      _logError('IdentifyUser', e);
    }
  }

  @override
  void dispose() {
    if (_isOffline) _saveDrawingsToHive();
    _localServer?.stop();
    super.dispose();
  }

  // 💾 --- Hive Logic (مع تسجيل أخطاء) ---
  Future<void> _saveDrawingsToHive() async {
    if (_pageDrawings.isEmpty) return;
    try {
      _logInfo("Saving drawings for PDF: ${widget.pdfId}");
      final box = await Hive.openBox('pdf_drawings_db');
      
      for (var entry in _pageDrawings.entries) {
        final page = entry.key;
        final lines = entry.value;
        if (lines.isNotEmpty) {
           final serialized = lines.map((l) => l.toJson()).toList();
           await box.put('${widget.pdfId}_$page', serialized);
        }
      }
    } catch (e, s) {
      _logError('HiveSave', e, s);
    }
  }

  Future<List<DrawingLine>> _getDrawingsForPage(int pageNumber) async {
    // 1. فحص الذاكرة أولاً (Cache)
    if (_pageDrawings.containsKey(pageNumber)) {
      return _pageDrawings[pageNumber]!;
    }
    
    // 2. التحميل من Hive
    try {
      final box = await Hive.openBox('pdf_drawings_db');
      final dynamic data = box.get('${widget.pdfId}_$pageNumber');
      
      List<DrawingLine> lines = [];
      if (data != null) {
        final List<dynamic> rawList = data;
        lines = rawList.map((e) => DrawingLine.fromJson(Map<String, dynamic>.from(e))).toList();
      }
      
      _pageDrawings[pageNumber] = lines; // حفظ في الذاكرة
      return lines;
    } catch (e, s) {
      _logError('HiveLoad_Page_$pageNumber', e, s);
      return [];
    }
  }

  // 🚀 --- تجهيز الملف ---
  Future<void> _preparePdf() async {
    setState(() => _loading = true);
    try {
      await EncryptionHelper.init();
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      // فحص الأوفلاين
      String? offlinePath;
      if (downloadItem != null && downloadItem['path'] != null) {
        offlinePath = downloadItem['path'];
        if (await File(offlinePath!).exists()) {
          _isOffline = true;
        } else {
           _logError('FileCheck', 'File path found in DB but file missing on disk: $offlinePath');
        }
      }

      _localServer?.stop();

      if (_isOffline) {
        _logInfo("Starting Offline Mode");
        // ✅ تشغيل السيرفر لفك التشفير
        _localServer = LocalPdfServer.offline(offlinePath, EncryptionHelper.key.base64);
      } else {
        _logInfo("Starting Online Mode");
        // ✅ تشغيل السيرفر كبروكسي
        var box = await Hive.openBox('auth_box');
        final headers = {
          'x-user-id': box.get('user_id')?.toString() ?? '',
          'x-device-id': box.get('device_id')?.toString() ?? '',
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        };
        final url = 'https://courses.aw478260.dpdns.org/api/secure/get-pdf?pdfId=${widget.pdfId}&t=${DateTime.now().millisecondsSinceEpoch}';
        _localServer = LocalPdfServer.online(url, headers);
      }

      int port = await _localServer!.start();
      _logInfo("Server running on port: $port");

      if (mounted) {
        setState(() {
          // مكتبة pdfrx تأخذ الرابط
          _filePath = 'http://127.0.0.1:$port/stream.pdf';
          _loading = false;
        });
      }
    } catch (e, s) {
      _logError('PreparePdf', e, s);
      if (mounted) setState(() { _error = "Failed to load PDF. Please check internet or storage."; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(body: Center(child: Text(_error!)));

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14, color: Colors.white)),
        backgroundColor: AppColors.backgroundSecondary,
        leading: BackButton(
          color: AppColors.accentYellow,
          onPressed: () async {
             if(_isOffline) await _saveDrawingsToHive();
             if(context.mounted) Navigator.pop(context);
          }
        ),
        actions: [
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
          // 1. عارض PDF (pdfrx)
          PdfViewer.uri(
            Uri.parse(_filePath!),
            controller: _pdfController,
            params: PdfViewerParams(
              enableTextSelection: false, // ⛔️ منع النسخ
              backgroundColor: AppColors.backgroundPrimary,
              
              // ✅ بناء الصفحة + الرسم
              pageBuilder: (context, pageRect, page, buildPage) {
                return Stack(
                  children: [
                    // أ. صفحة الـ PDF الأصلية
                    buildPage(context, pageRect, page),
                    
                    // ب. طبقة الرسم (فقط أوفلاين)
                    if (_isOffline)
                    Positioned.fill(
                      child: FutureBuilder<List<DrawingLine>>(
                        future: _getDrawingsForPage(page.pageNumber),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                             _logError('DrawingBuilder', snapshot.error!, snapshot.stackTrace);
                          }
                          
                          final lines = snapshot.data ?? [];
                          final allLines = [...lines];
                          
                          // إضافة الخط الجاري رسمه الآن
                          if (_isDrawingMode && _currentLine != null && _activePage == page.pageNumber) {
                            allLines.add(_currentLine!);
                          }

                          return IgnorePointer(
                            ignoring: !_isDrawingMode,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) {
                                if (!_isDrawingMode) return;
                                
                                // تحويل لنظام نسبي (0.0 - 1.0)
                                final renderBox = context.findRenderObject() as RenderBox;
                                final localPos = renderBox.globalToLocal(details.globalPosition);
                                final relativePoint = Offset(
                                  localPos.dx / pageRect.width,
                                  localPos.dy / pageRect.height,
                                );

                                setState(() {
                                  _activePage = page.pageNumber;
                                  _currentLine = DrawingLine(
                                    points: [relativePoint],
                                    color: _isHighlighter ? _highlightColor.value : _penColor.value,
                                    // استخدام الحجم النسبي المحدد
                                    strokeWidth: _isHighlighter ? _highlightSize : _penSize,
                                    isHighlighter: _isHighlighter,
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
                                  pageSize: pageRect.size, // الحجم الحالي للصفحة
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              onViewerReady: (document, controller) {
                _logInfo("PDF Loaded. Pages: ${document.pages.length}");
              },
              onError: (e) {
                 _logError('PdfViewError', e);
              },
            ),
          ),

          // 2. شريط الأدوات (يظهر عند التفعيل)
          if (_isDrawingMode && _isOffline)
            Positioned(
              bottom: 40, left: 20, right: 20,
              child: _buildToolbar(),
            ),
        ],
      ),
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
              _buildToolButton(LucideIcons.penTool, false),
              _buildToolButton(LucideIcons.highlighter, true),
              
              // زر التراجع
              IconButton(
                icon: const Icon(LucideIcons.undo, color: Colors.white),
                onPressed: () {
                   // تراجع عن آخر رسمة في الصفحة النشطة
                   if (_pageDrawings[_activePage]?.isNotEmpty ?? false) {
                     setState(() {
                       _pageDrawings[_activePage]!.removeLast();
                     });
                   }
                },
              ),

              Container(width: 1, height: 24, color: Colors.grey),
              
              _buildColorButton(Colors.black),
              _buildColorButton(Colors.red),
              _buildColorButton(Colors.blue),
              _buildColorButton(Colors.yellow, isHighlight: true),
              _buildColorButton(Colors.green, isHighlight: true),
            ],
          ),
          const SizedBox(height: 8),
          
          // Slider للتحكم في الحجم
          Row(
            children: [
              const Icon(LucideIcons.circle, size: 8, color: Colors.white70),
              Expanded(
                child: Slider(
                  // نغير الحدود بناءً على الأداة (القلم يحتاج سمك أقل من الهايلايت)
                  value: _isHighlighter ? _highlightSize : _penSize,
                  min: _isHighlighter ? 0.01 : 0.001,
                  max: _isHighlighter ? 0.08 : 0.01, 
                  activeColor: _isHighlighter ? _highlightColor : _penColor,
                  inactiveColor: Colors.grey,
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
              const Icon(LucideIcons.circle, size: 18, color: Colors.white70),
            ],
          ),
        ],
      ),
    );
  }
  
  // (نفس دوال _buildToolButton و _buildColorButton السابقة)
  Widget _buildToolButton(IconData icon, bool isHighlightTool) {
    final bool isSelected = _isHighlighter == isHighlightTool;
    return IconButton(
      icon: Icon(icon, color: isSelected ? AppColors.accentYellow : Colors.grey),
      onPressed: () => setState(() => _isHighlighter = isHighlightTool),
    );
  }

  Widget _buildColorButton(Color color, {bool isHighlight = false}) {
    final bool isSelected = _isHighlighter ? _highlightColor == color : _penColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_isHighlighter) { _highlightColor = color; } else { _penColor = color; }
          if (isHighlight) _isHighlighter = true;
          if (!isHighlight && (color != Colors.yellow && color != Colors.green)) _isHighlighter = false;
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

// 🎨 الرسام النسبي (Relative Painter)
class RelativeSketchPainter extends CustomPainter {
  final List<DrawingLine> lines;
  final Size pageSize;

  RelativeSketchPainter({required this.lines, required this.pageSize});

  @override
  void paint(Canvas canvas, Size size) {
    for (var line in lines) {
      final paint = Paint()
        ..color = Color(line.color).withOpacity(line.isHighlighter ? 0.35 : 1.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = line.isHighlighter ? StrokeCap.butt : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        // 🔑 تحويل السمك النسبي إلى بكسل حقيقي بناءً على عرض الصفحة
        ..strokeWidth = line.strokeWidth * pageSize.width; 

      if (line.isHighlighter) paint.blendMode = BlendMode.darken; 

      if (line.points.length > 1) {
        final path = Path();
        // 🔑 تحويل الإحداثيات النسبية إلى بكسل
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
