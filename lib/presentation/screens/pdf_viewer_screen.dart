import 'dart:io';
import 'dart:async';
import 'dart:isolate'; // ✅ استيراد مكتبة العزل
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:device_info_plus/device_info_plus.dart'; 
import 'package:encrypt/encrypt.dart' as encrypt; // ✅ نحتاج المكتبة داخل العزل
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/encryption_helper.dart';

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
  String? _localFilePath; 
  bool _loading = true;
  double _progressValue = 0.0;
  String _loadingMessage = "Preparing...";
  
  bool _isWeakDevice = false;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;
  
  String _watermarkText = '';
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  
  // للتحكم في العزل وإيقافه عند الخروج
  Isolate? _decryptIsolate;
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("📄 PDF Screen Opened: ${widget.title}");
    _checkDevicePerformance();
    _initWatermarkText();
    _loadPdf();
  }

  Future<void> _checkDevicePerformance() async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        // الأجهزة القديمة (Android 9 / API 28 وما قبل)
        if (androidInfo.version.sdkInt <= 28) {
          if (mounted) setState(() => _isWeakDevice = true);
        }
      } catch (e) { /* ignore */ }
    }
  }

  @override
  void dispose() {
    // ✅ إيقاف العزل عند الخروج لتنظيف الموارد
    _decryptIsolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();

    // تنظيف الملف المؤقت
    if (_localFilePath != null) {
      final file = File(_localFilePath!);
      if (file.existsSync()) {
        try {
          file.deleteSync(); 
        } catch (e) { /* ignore */ }
      }
    }
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

  // ===========================================================================
  // ✅ منطقة العزل (Isolate Logic)
  // ===========================================================================

  // دالة لتجهيز وتشغيل العزل
  Future<void> _spawnDecryptIsolate(String sourcePath, String destPath, String keyBase64) async {
    _receivePort = ReceivePort();
    
    _decryptIsolate = await Isolate.spawn(
      _decryptInIsolate,
      _DecryptInitData(_receivePort!.sendPort, sourcePath, destPath, keyBase64),
    );

    // الاستماع لرسائل العزل (نسبة التقدم أو الانتهاء)
    await for (final message in _receivePort!) {
      if (message is double) {
        // تحديث نسبة التقدم
        if (mounted) {
          setState(() {
            _progressValue = message;
            _loadingMessage = "Decrypting... ${(message * 100).toInt()}%";
          });
        }
      } else if (message == "DONE") {
        // انتهت العملية بنجاح
        if (mounted) {
          setState(() {
            _localFilePath = destPath;
            _loading = false;
          });
        }
        break; // الخروج من حلقة الاستماع
      } else if (message is String && message.startsWith("ERROR")) {
        throw Exception(message);
      }
    }
  }

  // ⚠️ هذه الدالة تعمل في ذاكرة منفصلة (Background Thread)
  static void _decryptInIsolate(_DecryptInitData initData) async {
    try {
      final sourceFile = File(initData.sourcePath);
      final destFile = File(initData.destPath);
      
      // إعداد التشفير يدوياً داخل العزل
      final key = encrypt.Key.fromBase64(initData.keyBase64);
      final ivLength = 12; 
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

      final raf = await sourceFile.open(mode: FileMode.read);
      final sink = destFile.openWrite();
      
      final fileLength = await sourceFile.length();
      int currentPos = 0;
      
      // حجم البلوك (نفس المستخدم في EncryptionHelper)
      // IV(12) + Data(128KB) + Tag(16)
      const int plainBlockSize = 128 * 1024; 
      const int encryptedBlockSize = 12 + plainBlockSize + 16; 

      // للتحكم في معدل إرسال الرسائل للخيط الرئيسي (Throttle)
      int lastReportTime = 0;

      while (currentPos < fileLength) {
        int bytesToRead = encryptedBlockSize;
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }

        Uint8List chunk = await raf.read(bytesToRead);
        if (chunk.isEmpty) break;

        // منطق فك التشفير
        try {
          final iv = encrypt.IV(chunk.sublist(0, ivLength));
          final cipherText = chunk.sublist(ivLength);
          final decrypted = encrypter.decryptBytes(encrypt.Encrypted(cipherText), iv: iv);
          sink.add(decrypted);
        } catch (e) {
          // في حال فشل جزء، نتجاوزه لتجنب توقف الملف بالكامل
          print("Decrypt Error in chunk: $e");
        }

        currentPos += chunk.length;

        // إرسال التحديث كل 100 ميلي ثانية تقريباً
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastReportTime > 100) {
          initData.sendPort.send(currentPos / fileLength);
          lastReportTime = now;
        }
      }

      await raf.close();
      await sink.flush();
      await sink.close();

      initData.sendPort.send("DONE");

    } catch (e) {
      initData.sendPort.send("ERROR: $e");
    }
  }

  // ===========================================================================

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _loadingMessage = "Checking file...";
    });

    try {
      await EncryptionHelper.init(); // التأكد من جلب المفتاح

      // 1. التعامل مع الملفات الأوفلاين
      final downloadsBox = await Hive.openBox('downloads_box');
      final downloadItem = downloadsBox.get(widget.pdfId);

      if (downloadItem != null && downloadItem['path'] != null) {
        final String encryptedPath = downloadItem['path'];
        final File encryptedFile = File(encryptedPath);
        
        if (await encryptedFile.exists()) {
          // إنشاء مسار للملف المؤقت المفكوك
          final dir = await getTemporaryDirectory();
          final tempPath = '${dir.path}/temp_pdf_${DateTime.now().millisecondsSinceEpoch}.pdf';
          
          // ✅ تشغيل العزل لفك التشفير
          // نمرر المفتاح كنص لأن الكائنات المعقدة لا تنتقل عبر العزل
          await _spawnDecryptIsolate(
            encryptedPath, 
            tempPath, 
            EncryptionHelper.key.base64
          );
          return; 
        }
      }

      // 2. التحميل من الإنترنت (Online)
      if (mounted) setState(() {
         _loadingMessage = "Downloading...";
      });

      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      final deviceId = box.get('device_id');

      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/online_${widget.pdfId}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      int lastUpdateTimestamp = 0;

      await dio.download(
        'https://courses.aw478260.dpdns.org/api/secure/get-pdf',
        savePath,
        queryParameters: {'pdfId': widget.pdfId},
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final now = DateTime.now().millisecondsSinceEpoch;
            // تحديث الواجهة بتروٍ (كل 250ms)
            if (now - lastUpdateTimestamp > 250) {
              lastUpdateTimestamp = now;
              if (mounted) {
                setState(() {
                  _progressValue = received / total;
                  _loadingMessage = "Downloading... ${(_progressValue * 100).toInt()}%";
                });
              }
            }
          }
        },
      );

      if (mounted) {
        setState(() {
          _localFilePath = savePath;
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
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularPercentIndicator(
                radius: 45.0,
                lineWidth: 5.0,
                percent: _progressValue,
                center: Text(
                  "${(_progressValue * 100).toInt()}%",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
                progressColor: AppColors.accentYellow,
                backgroundColor: Colors.white10,
              ),
              const SizedBox(height: 20),
              Text(
                _loadingMessage, 
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)
              ),
              if (_isWeakDevice)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    "Optimizing for your device...",
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
            ],
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
          _buildPdfViewer(),

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

  Widget _buildPdfViewer() {
    // للأجهزة الضعيفة، نستخدم التمرير العمودي المستمر لأنه آمن الآن مع الملفات المؤقتة
    const layoutMode = PdfPageLayoutMode.continuous;
    const scrollDirection = PdfScrollDirection.vertical;

    if (_localFilePath != null) {
      return SfPdfViewer.file(
        File(_localFilePath!),
        key: _pdfViewerKey,
        enableDoubleTapZooming: !_isWeakDevice, // تعطيل التكبير المزدوج للأجهزة الضعيفة جداً
        enableTextSelection: false,
        pageLayoutMode: layoutMode,
        scrollDirection: scrollDirection,
        canShowScrollHead: true, 
        onDocumentLoaded: (details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onPageChanged: (details) {
          setState(() => _currentPage = details.newPageNumber - 1);
        },
      );
    }
    return const SizedBox.shrink();
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

// ✅ كلاس لنقل البيانات للعزل (يجب أن يكون خارج أي كلاس آخر)
class _DecryptInitData {
  final SendPort sendPort;
  final String sourcePath;
  final String destPath;
  final String keyBase64;

  _DecryptInitData(this.sendPort, this.sourcePath, this.destPath, this.keyBase64);
}
