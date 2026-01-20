import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// تأكد من المسار الصحيح لملف التشفير الخاص بك
import '../utils/encryption_helper.dart';

class LocalPdfServer {
  HttpServer? _server;
  final String encryptedFilePath;
  final String keyBase64;
  
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;

  // إعدادات التشفير (يجب أن تطابق إعدادات التشفير وقت التحميل)
  static const int plainBlockSize = 32 * 1024; // 32KB Data
  static const int ivLength = 12;
  static const int tagLength = 16;
  static const int encryptedBlockSize = ivLength + plainBlockSize + tagLength;

  LocalPdfServer(this.encryptedFilePath, this.keyBase64);

  void _log(String message) {
    // تسجيل الأخطاء المهمة فقط في الفايربيس لتوفير الموارد
    if (message.contains("ERROR") || message.contains("FATAL")) {
      print("🔍 [PDF_SERVER] $message");
      try {
        FirebaseCrashlytics.instance.log("PDF_SERVER: $message");
      } catch (_) {}
    }
  }

  Future<int> start() async {
    final file = File(encryptedFilePath);
    if (!await file.exists()) {
      throw Exception("File not found at $encryptedFilePath");
    }

    // تهيئة المعالج في الخلفية
    final initPort = ReceivePort();
    _workerIsolate = await Isolate.spawn(_decryptWorkerEntry, initPort.sendPort);
    _workerSendPort = await initPort.first as SendPort;

    // بدء السيرفر
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleHttpRequest);
    
    return _server!.port;
  }

  Future<void> stop() async {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    await _server?.close(force: true);
    _server = null;
  }

  void _handleHttpRequest(HttpRequest request) async {
    final response = request.response;

    try {
      final file = File(encryptedFilePath);
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final encryptedLen = await file.length();

      // ✅ 1. الحساب الدقيق للحجم (يمنع خطأ Content size mismatch)
      final int fullBlocks = encryptedLen ~/ encryptedBlockSize;
      final int remainingBytes = encryptedLen % encryptedBlockSize;
      
      // حماية: إذا تبقى بايتات أقل من حجم الهيدر، نعتبرها صفر (ملف تالف أو نهاية دقيقة)
      final int lastBlockSize = remainingBytes > (ivLength + tagLength) 
          ? (remainingBytes - ivLength - tagLength) 
          : 0;
          
      final int originalSize = (fullBlocks * plainBlockSize) + lastBlockSize;

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, 'application/pdf');

      int start = 0;
      int end = originalSize - 1;

      String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      if (rangeHeader != null) {
        // ✅ 2. دعم الـ Streaming والتنقل (Range Request)
        try {
          final range = rangeHeader.split('=')[1].split('-');
          start = int.parse(range[0]);
          if (range.length > 1 && range[1].isNotEmpty) {
            end = int.parse(range[1]);
          }
          if (end >= originalSize) end = originalSize - 1;

          response.statusCode = HttpStatus.partialContent;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$originalSize');
        } catch (e) {
          // في حال فشل قراءة الرينج، نرسل الملف كاملاً
          response.statusCode = HttpStatus.ok;
          start = 0;
          end = originalSize - 1;
        }
      } else {
        // طلب عادي (كامل الملف)
        response.statusCode = HttpStatus.ok;
      }

      // ✅ 3. تحديد الحجم بدقة (يسمح للمشغل بالعرض الفوري دون انتظار)
      response.contentLength = end - start + 1;

      if (request.method != 'HEAD') {
        final streamResponsePort = ReceivePort();
        
        // إرسال طلب فك التشفير للمعالج
        _workerSendPort!.send(_DecryptRequest(
          filePath: encryptedFilePath,
          keyBase64: keyBase64,
          startByte: start,
          endByte: end,
          replyPort: streamResponsePort.sendPort,
        ));

        // استقبال البيانات وبثها
        await for (final chunk in streamResponsePort) {
          if (chunk is Uint8List) {
            response.add(chunk);
          } else if (chunk == null) {
            break; 
          }
        }
        streamResponsePort.close();
      }
      
      await response.close();

    } catch (e, s) {
      // تجاهل أخطاء إغلاق الاتصال المعتادة من المتصفحات/العارض
      if (!e.toString().contains("Connection closed") && 
          !e.toString().contains("Broken pipe")) {
         _log("Handler Error: $e");
         FirebaseCrashlytics.instance.recordError(e, s, reason: 'LocalServer Error');
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }

  // ===========================================================================
  // ⚙️ منطقة المعالج المعزول (Worker Isolate)
  // ===========================================================================

  static void _decryptWorkerEntry(SendPort initSendPort) {
    final commandPort = ReceivePort();
    initSendPort.send(commandPort.sendPort);

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

      int startBlockIndex = req.startByte ~/ plainBlockSize;
      int endBlockIndex = req.endByte ~/ plainBlockSize;
      int offsetInFirstBlock = req.startByte % plainBlockSize;
      
      int bytesSent = 0;
      int totalBytesToSend = req.endByte - req.startByte + 1;

      for (int i = startBlockIndex; i <= endBlockIndex; i++) {
        if (bytesSent >= totalBytesToSend) break;

        // حساب موقع القراءة
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
          // فك التشفير
          final iv = encrypt.IV(encryptedChunk.sublist(0, ivLength));
          final cipherText = encryptedChunk.sublist(ivLength);
          
          List<int> decryptedBlock = encrypter.decryptBytes(
            encrypt.Encrypted(cipherText), 
            iv: iv
          );

          // تحديد الجزء المطلوب من البلوك المفكوك
          int chunkStart = (i == startBlockIndex) ? offsetInFirstBlock : 0;
          int chunkEnd = decryptedBlock.length;
          int remainingBytesNeeded = totalBytesToSend - bytesSent;

          if (chunkEnd - chunkStart > remainingBytesNeeded) {
            chunkEnd = chunkStart + remainingBytesNeeded;
          }

          if (chunkStart < chunkEnd) {
            req.replyPort.send(Uint8List.fromList(decryptedBlock.sublist(chunkStart, chunkEnd)));
            bytesSent += (chunkEnd - chunkStart);
          }
        } catch (e) {
           print("Worker: Decrypt Block Error at index $i: $e");
           // يمكن هنا إرسال بايتات فارغة للحفاظ على التزامن إذا لزم الأمر
        }
      }
    } catch (e) {
      print("Worker Fatal Error: $e");
    } finally {
      await raf?.close();
      req.replyPort.send(null); // إشارة الانتهاء
    }
  }
}

// كلاس نقل البيانات للعزل
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
