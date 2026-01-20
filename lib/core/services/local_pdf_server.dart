import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/encryption_helper.dart';

class LocalPdfServer {
  HttpServer? _server;
  final String? encryptedFilePath;
  final String? keyBase64;
  final String? onlineUrl;
  final Map<String, String>? onlineHeaders;

  Isolate? _workerIsolate;
  SendPort? _workerSendPort;

  // إعدادات حجم الكتل (يجب أن تطابق إعدادات التشفير)
  static const int plainBlockSize = 32 * 1024; 
  static const int ivLength = 12;
  static const int tagLength = 16;
  static const int encryptedBlockSize = ivLength + plainBlockSize + tagLength;

  LocalPdfServer.offline(this.encryptedFilePath, this.keyBase64) 
      : onlineUrl = null, onlineHeaders = null;

  LocalPdfServer.online(this.onlineUrl, this.onlineHeaders) 
      : encryptedFilePath = null, keyBase64 = null;

  Future<int> start() async {
    // تشغيل العمليات الخلفية لفك التشفير فقط في حالة الأوفلاين
    if (encryptedFilePath != null) {
      final initPort = ReceivePort();
      _workerIsolate = await Isolate.spawn(_decryptWorkerEntry, initPort.sendPort);
      _workerSendPort = await initPort.first as SendPort;
    }

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleHttpRequest);
    return _server!.port;
  }

  Future<void> stop() async {
    _workerIsolate?.kill(priority: Isolate.immediate);
    await _server?.close(force: true);
  }

  void _handleHttpRequest(HttpRequest request) async {
    try {
      // =========================================================
      // 🌐 1. أونلاين: نفق مباشر (Streaming Tunnel)
      // =========================================================
      if (onlineUrl != null) {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        
        final proxyRequest = await client.getUrl(Uri.parse(onlineUrl!));

        // نسخ الهيدرز
        onlineHeaders?.forEach((k, v) => proxyRequest.headers.set(k, v));
        
        // 🔥 تحويل Range إلى X-Alt-Range ليقبله الباك اند
        if (request.headers.value(HttpHeaders.rangeHeader) != null) {
          final rangeVal = request.headers.value(HttpHeaders.rangeHeader)!;
          proxyRequest.headers.set('X-Alt-Range', rangeVal);
          // طباعة لمعرفة ما يطلبه العارض في الأونلاين
          print("🌐 Online Request Range: $rangeVal");
        }

        final proxyResponse = await proxyRequest.close();

        request.response.statusCode = proxyResponse.statusCode;
        request.response.headers.contentType = proxyResponse.headers.contentType;
        request.response.contentLength = proxyResponse.contentLength;
        
        proxyResponse.headers.forEach((name, values) {
           if (name.toLowerCase() == 'content-range' || 
               name.toLowerCase() == 'accept-ranges') {
             request.response.headers.set(name, values);
           }
        });

        await request.response.addStream(proxyResponse);
        await request.response.close();
        return;
      }

      // =========================================================
      // 📂 2. أوفلاين: فك تشفير جزئي (Random Access Decryption)
      // =========================================================
      final response = request.response;
      final file = File(encryptedFilePath!);
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      // حساب الحجم الأصلي (مفكوك التشفير) ليظهر للعارض كملف طبيعي
      final encryptedLen = await file.length();
      final int fullBlocks = encryptedLen ~/ encryptedBlockSize;
      final int remainingBytes = encryptedLen % encryptedBlockSize;
      final int lastBlockSize = remainingBytes > (ivLength + tagLength) 
          ? (remainingBytes - ivLength - tagLength) : 0;
      final int originalSize = (fullBlocks * plainBlockSize) + lastBlockSize;

      // إخبار العارض أننا ندعم طلب الأجزاء
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, 'application/pdf');

      int start = 0;
      int end = originalSize - 1;
      String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      if (rangeHeader != null) {
        // طباعة لمعرفة هل العارض يطلب جزءاً أم الملف كاملاً
        print("📂 Offline Request Range: $rangeHeader (Total: $originalSize)");
        
        try {
          final range = rangeHeader.split('=')[1].split('-');
          start = int.parse(range[0]);
          if (range.length > 1 && range[1].isNotEmpty) end = int.parse(range[1]);
          // تصحيح النهاية إذا تجاوزت الحجم
          if (end >= originalSize) end = originalSize - 1;
          
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$originalSize');
        } catch (_) {
           response.statusCode = HttpStatus.ok;
        }
      } else {
        print("📂 Offline Request: Full File (No Range)");
        response.statusCode = HttpStatus.ok;
      }

      response.contentLength = end - start + 1;

      if (request.method != 'HEAD') {
        final streamResponsePort = ReceivePort();
        
        // إرسال طلب للعامل (Isolate) لفك تشفير *الجزء المطلوب فقط*
        _workerSendPort!.send(_DecryptRequest(
          filePath: encryptedFilePath!,
          keyBase64: keyBase64!,
          startByte: start, // يبدأ الفك من هنا
          endByte: end,     // يتوقف هنا
          replyPort: streamResponsePort.sendPort,
        ));

        // استقبال البيانات المتدفقة وإرسالها للعارض فوراً
        await for (final chunk in streamResponsePort) {
          if (chunk is Uint8List) {
            response.add(chunk);
          } else if (chunk == null) {
            break; // انتهى البيانات
          }
        }
        streamResponsePort.close();
      }
      await response.close();

    } catch (e) {
      try { await request.response.close(); } catch (_) {}
    }
  }

  // --- منطق العزل (Isolate Logic) ---
  // هذا الجزء يعمل في Thread منفصل لضمان عدم تجميد الواجهة
  static void _decryptWorkerEntry(SendPort initSendPort) {
    final commandPort = ReceivePort();
    initSendPort.send(commandPort.sendPort);
    commandPort.listen((message) {
      if (message is _DecryptRequest) _processDecryption(message);
    });
  }

  static Future<void> _processDecryption(_DecryptRequest req) async {
    final file = File(req.filePath);
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final key = encrypt.Key.fromBase64(req.keyBase64);
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

      // تحديد أي الكتل (Blocks) نحتاج قراءتها بناءً على الـ Range المطلوب
      int startBlockIndex = req.startByte ~/ plainBlockSize;
      int endBlockIndex = req.endByte ~/ plainBlockSize;
      int offsetInFirstBlock = req.startByte % plainBlockSize;
      
      int bytesSent = 0;
      int totalBytesToSend = req.endByte - req.startByte + 1;

      // حلقة تكرارية تقرأ وتفك تشفير الكتل المطلوبة فقط
      for (int i = startBlockIndex; i <= endBlockIndex; i++) {
        if (bytesSent >= totalBytesToSend) break;

        // القفز مباشرة لمكان الكتلة المشفرة (Random Access)
        int filePos = i * encryptedBlockSize;
        await raf.setPosition(filePos);
        
        int readSize = encryptedBlockSize;
        int fileLen = await file.length();
        if (filePos + readSize > fileLen) readSize = fileLen - filePos;
        if (readSize <= ivLength + tagLength) break;

        Uint8List encryptedChunk = await raf.read(readSize);
        try {
          final iv = encrypt.IV(encryptedChunk.sublist(0, ivLength));
          final cipherText = encryptedChunk.sublist(ivLength);
          List<int> decryptedBlock = encrypter.decryptBytes(encrypt.Encrypted(cipherText), iv: iv);

          // حساب الجزء المطلوب من الكتلة (لأن الطلب قد يبدأ من منتصف الكتلة)
          int chunkStart = (i == startBlockIndex) ? offsetInFirstBlock : 0;
          int chunkEnd = decryptedBlock.length;
          
          if (chunkEnd - chunkStart > (totalBytesToSend - bytesSent)) {
            chunkEnd = chunkStart + (totalBytesToSend - bytesSent);
          }

          if (chunkStart < chunkEnd) {
            // إرسال القطعة المفكوكة للمسار الرئيسي فوراً
            req.replyPort.send(Uint8List.fromList(decryptedBlock.sublist(chunkStart, chunkEnd)));
            bytesSent += (chunkEnd - chunkStart);
          }
        } catch (_) {}
      }
    } catch (_) {} finally {
      await raf?.close();
      req.replyPort.send(null); // إشارة النهاية
    }
  }
}

class _DecryptRequest {
  final String filePath;
  final String keyBase64;
  final int startByte;
  final int endByte;
  final SendPort replyPort;
  _DecryptRequest({required this.filePath, required this.keyBase64, required this.startByte, required this.endByte, required this.replyPort});
}
