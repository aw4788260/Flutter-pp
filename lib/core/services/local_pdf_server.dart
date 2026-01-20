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

  static const int plainBlockSize = 32 * 1024; 
  static const int ivLength = 12;
  static const int tagLength = 16;
  static const int encryptedBlockSize = ivLength + plainBlockSize + tagLength;

  LocalPdfServer.offline(this.encryptedFilePath, this.keyBase64) 
      : onlineUrl = null, onlineHeaders = null;

  LocalPdfServer.online(this.onlineUrl, this.onlineHeaders) 
      : encryptedFilePath = null, keyBase64 = null;

  Future<int> start() async {
    // تشغيل الـ Worker فقط في حالة الأوفلاين لفك التشفير
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
      // ---------------------------------------------------------
      // 🌐 1. أونلاين: نفق مباشر (Streaming Tunnel)
      // ---------------------------------------------------------
      if (onlineUrl != null) {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        // 🔥 منع Dart من تخريب هيدر الحجم
        client.autoUncompress = false; 
        
        final proxyRequest = await client.getUrl(Uri.parse(onlineUrl!));
        onlineHeaders?.forEach((k, v) => proxyRequest.headers.set(k, v));
        
        // تمرير الـ Range لدعم البث
        if (request.headers.value(HttpHeaders.rangeHeader) != null) {
          final rangeVal = request.headers.value(HttpHeaders.rangeHeader)!;
          proxyRequest.headers.set(HttpHeaders.rangeHeader, rangeVal);
        }

        final proxyResponse = await proxyRequest.close();

        request.response.statusCode = proxyResponse.statusCode;
        proxyResponse.headers.forEach((name, values) {
            request.response.headers.set(name, values);
        });
        
        if (proxyResponse.contentLength != -1) {
            request.response.contentLength = proxyResponse.contentLength;
        }

        await request.response.addStream(proxyResponse);
        await request.response.close();
        return;
      }

      // ---------------------------------------------------------
      // 📂 2. أوفلاين: فك تشفير سريع مع كاش
      // ---------------------------------------------------------
      final file = File(encryptedFilePath!);
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      // حساب الحجم الأصلي للملف (بدون بايتات التشفير)
      final encryptedLen = await file.length();
      final int fullBlocks = encryptedLen ~/ encryptedBlockSize;
      final int remainingBytes = encryptedLen % encryptedBlockSize;
      final int lastBlockSize = remainingBytes > (ivLength + tagLength) 
          ? (remainingBytes - ivLength - tagLength) : 0;
      final int originalSize = (fullBlocks * plainBlockSize) + lastBlockSize;

      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/pdf');

      int start = 0;
      int end = originalSize - 1;
      String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      if (rangeHeader != null) {
        try {
          final range = rangeHeader.split('=')[1].split('-');
          start = int.parse(range[0]);
          if (range.length > 1 && range[1].isNotEmpty) end = int.parse(range[1]);
          if (end >= originalSize) end = originalSize - 1;
          
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$originalSize');
        } catch (_) {
           request.response.statusCode = HttpStatus.ok;
        }
      } else {
        request.response.statusCode = HttpStatus.ok;
      }

      request.response.contentLength = end - start + 1;

      if (request.method != 'HEAD') {
        final streamResponsePort = ReceivePort();
        
        // إرسال طلب للعامل
        _workerSendPort!.send(_DecryptRequest(
          filePath: encryptedFilePath!,
          keyBase64: keyBase64!,
          startByte: start,
          endByte: end,
          replyPort: streamResponsePort.sendPort,
        ));

        // استقبال البيانات المتدفقة
        await for (final chunk in streamResponsePort) {
          if (chunk is Uint8List) {
            request.response.add(chunk);
          } else if (chunk == null) {
            break;
          }
        }
        streamResponsePort.close();
      }
      await request.response.close();

    } catch (e) {
      try { await request.response.close(); } catch (_) {}
    }
  }

  // --- Worker Isolate (مع نظام الكاش) ---
  static void _decryptWorkerEntry(SendPort initSendPort) {
    final commandPort = ReceivePort();
    initSendPort.send(commandPort.sendPort);

    // ✅ الكاش: نخزن آخر 100 كتلة (حوالي 3MB) في الذاكرة لتسريع التصفح
    final Map<int, Uint8List> memoryCache = {};
    final List<int> lruKeys = [];
    const int maxCacheSize = 100; 

    commandPort.listen((message) {
      if (message is _DecryptRequest) {
        _processDecryptionSmart(message, memoryCache, lruKeys, maxCacheSize);
      }
    });
  }

  static Future<void> _processDecryptionSmart(
      _DecryptRequest req, 
      Map<int, Uint8List> cache, 
      List<int> lruKeys,
      int maxCacheLimit
  ) async {
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

        Uint8List decryptedBlock;

        // 1. هل الكتلة موجودة في الكاش؟
        if (cache.containsKey(i)) {
          decryptedBlock = cache[i]!;
          // تحديث الترتيب (الأحدث استخداماً)
          lruKeys.remove(i);
          lruKeys.add(i);
        } else {
          // 2. غير موجودة، نقرأ من القرص ونفك التشفير
          int filePos = i * encryptedBlockSize;
          await raf.setPosition(filePos);
          
          int readSize = encryptedBlockSize;
          int fileLen = await file.length();
          if (filePos + readSize > fileLen) readSize = fileLen - filePos;
          
          // إذا وصلنا للنهاية أو خطأ
          if (readSize <= ivLength + tagLength) break;

          Uint8List encryptedChunk = await raf.read(readSize);
          try {
            final iv = encrypt.IV(encryptedChunk.sublist(0, ivLength));
            final cipherText = encryptedChunk.sublist(ivLength);
            
            // فك التشفير
            List<int> bytes = encrypter.decryptBytes(encrypt.Encrypted(cipherText), iv: iv);
            decryptedBlock = Uint8List.fromList(bytes);

            // الحفظ في الكاش
            cache[i] = decryptedBlock;
            lruKeys.add(i);

            // تنظيف الكاش إذا امتلأ
            if (lruKeys.length > maxCacheLimit) {
              int oldKey = lruKeys.removeAt(0);
              cache.remove(oldKey);
            }
          } catch (_) {
            continue; // تخطي الكتل التالفة
          }
        }

        // إرسال الجزء المطلوب فقط من الكتلة
        int chunkStart = (i == startBlockIndex) ? offsetInFirstBlock : 0;
        int chunkEnd = decryptedBlock.length;
        
        // ضبط النهاية بناءً على الكمية المطلوبة
        if (chunkEnd - chunkStart > (totalBytesToSend - bytesSent)) {
          chunkEnd = chunkStart + (totalBytesToSend - bytesSent);
        }

        if (chunkStart < chunkEnd) {
          req.replyPort.send(decryptedBlock.sublist(chunkStart, chunkEnd));
          bytesSent += (chunkEnd - chunkStart);
        }
      }
    } catch (_) {} finally {
      await raf?.close();
      req.replyPort.send(null); // علامة النهاية
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
