import 'dart:io';
import 'dart:async';
import 'dart:isolate'; // ✅ استيراد مكتبة العزل
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class LocalPdfServer {
  HttpServer? _server;
  final String encryptedFilePath;
  final String keyBase64;
  
  // ✅ متغيرات التواصل مع المعالج في الخلفية
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;

  // إعدادات التشفير (يجب أن تطابق إعدادات التشفير وقت التحميل)
  static const int plainBlockSize = 32 * 1024; // 32KB Chunk
  static const int ivLength = 12;
  static const int tagLength = 16;
  static const int encryptedBlockSize = ivLength + plainBlockSize + tagLength;

  LocalPdfServer(this.encryptedFilePath, this.keyBase64);

  Future<int> start() async {
    // 1. تشغيل المعالج (Isolate) في الخلفية
    final initPort = ReceivePort();
    _workerIsolate = await Isolate.spawn(_decryptWorkerEntry, initPort.sendPort);
    
    // استلام بورت الإرسال الخاص بالمعالج
    _workerSendPort = await initPort.first as SendPort;

    // 2. تشغيل سيرفر HTTP المحلي
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleHttpRequest);
    
    return _server!.port;
  }

  Future<void> stop() async {
    // قتل المعالج وتنظيف السيرفر
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    await _server?.close(force: true);
    _server = null;
  }

  void _handleHttpRequest(HttpRequest request) async {
    final response = request.response;
    final file = File(encryptedFilePath);

    try {
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final encryptedLen = await file.length();
      // حساب الحجم التقريبي للملف الأصلي
      final originalSize = (encryptedLen / encryptedBlockSize * plainBlockSize).toInt();

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, 'application/pdf');

      // معالجة الـ Range Request (للتنقل السريع)
      String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      int start = 0;
      int end = originalSize - 1;

      if (rangeHeader != null) {
        final range = rangeHeader.split('=')[1].split('-');
        start = int.parse(range[0]);
        if (range.length > 1 && range[1].isNotEmpty) {
          end = int.parse(range[1]);
        }
        if (end >= originalSize) end = originalSize - 1;

        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$originalSize');
      } else {
        response.statusCode = HttpStatus.ok;
      }

      response.contentLength = end - start + 1;

      if (request.method != 'HEAD') {
        // ✅ إنشاء قناة استقبال خاصة بهذا الطلب فقط
        final streamResponsePort = ReceivePort();
        
        // ✅ إرسال طلب العمل للخيط المنفصل (Background Isolate)
        _workerSendPort!.send(_DecryptRequest(
          filePath: encryptedFilePath,
          keyBase64: keyBase64,
          startByte: start,
          endByte: end,
          replyPort: streamResponsePort.sendPort,
        ));

        // ✅ استقبال البيانات المفكوكة وتمريرها للمشغل فوراً
        await for (final chunk in streamResponsePort) {
          if (chunk is Uint8List) {
            response.add(chunk);
            // flush اختياري لضمان سلاسة البث
            await response.flush(); 
          } else if (chunk == null) {
            break; // إشارة الانتهاء من المعالج
          }
        }
        streamResponsePort.close();
      }
      
      await response.close();

    } catch (e) {
      print("Server Error: $e");
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  // ===========================================================================
  // ⚙️ منطقة المعالج المعزول (Runs in Parallel Background Thread)
  // ===========================================================================
  
  static void _decryptWorkerEntry(SendPort initSendPort) {
    // إنشاء بورت لاستقبال الأوامر داخل العزل
    final commandPort = ReceivePort();
    // إرسال عنوان البورت للخيط الرئيسي
    initSendPort.send(commandPort.sendPort);

    // الاستماع للطلبات
    commandPort.listen((message) {
      if (message is _DecryptRequest) {
        _processDecryption(message);
      }
    });
  }

  static Future<void> _processDecryption(_DecryptRequest req) async {
    final file = File(req.filePath);
    RandomAccessFile? raf;

    try {
      raf = await file.open(mode: FileMode.read);
      final key = encrypt.Key.fromBase64(req.keyBase64);
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

      // تحديد البلوكات المطلوبة
      int startBlockIndex = req.startByte ~/ plainBlockSize;
      int endBlockIndex = req.endByte ~/ plainBlockSize;
      int offsetInFirstBlock = req.startByte % plainBlockSize;
      
      int bytesSent = 0;
      int totalBytesToSend = req.endByte - req.startByte + 1;

      for (int i = startBlockIndex; i <= endBlockIndex; i++) {
        if (bytesSent >= totalBytesToSend) break;

        // القراءة من القرص (Disk I/O) داخل العزل
        int filePos = i * encryptedBlockSize;
        await raf.setPosition(filePos);

        int readSize = encryptedBlockSize;
        int fileLen = await file.length();
        if (filePos + readSize > fileLen) {
          readSize = fileLen - filePos;
        }

        if (readSize <= ivLength + tagLength) break;

        Uint8List encryptedChunk = await raf.read(readSize);

        try {
          // 🔓 فك التشفير (Heavy CPU Work) داخل العزل
          final iv = encrypt.IV(encryptedChunk.sublist(0, ivLength));
          final cipherText = encryptedChunk.sublist(ivLength);
          
          List<int> decryptedBlock = encrypter.decryptBytes(
            encrypt.Encrypted(cipherText), 
            iv: iv
          );

          // حساب القص الدقيق للبيانات المطلوبة
          int chunkStart = (i == startBlockIndex) ? offsetInFirstBlock : 0;
          int chunkEnd = decryptedBlock.length;
          int remainingBytesNeeded = totalBytesToSend - bytesSent;

          if (chunkEnd - chunkStart > remainingBytesNeeded) {
            chunkEnd = chunkStart + remainingBytesNeeded;
          }

          if (chunkStart < chunkEnd) {
             // 📤 إرسال البيانات الجاهزة للخيط الرئيسي
            req.replyPort.send(Uint8List.fromList(decryptedBlock.sublist(chunkStart, chunkEnd)));
            bytesSent += (chunkEnd - chunkStart);
          }
        } catch (e) {
          print("Decrypt Worker Error at block $i: $e");
        }
      }
    } catch (e) {
      print("Worker Fatal Error: $e");
    } finally {
      await raf?.close();
      // إرسال null كإشارة لانتهاء العملية
      req.replyPort.send(null); 
    }
  }
}

// 📦 كلاس لنقل بيانات الطلب للعزل
class _DecryptRequest {
  final String filePath;
  final String keyBase64;
  final int startByte;
  final int endByte;
  final SendPort replyPort;

  _DecryptRequest({
    required this.filePath,
    required this.keyBase64,
    required this.startByte,
    required this.endByte,
    required this.replyPort,
  });
}
