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
      // 🌐 1. أونلاين: إصلاح جذري لمشكلة البث
      // =========================================================
      if (onlineUrl != null) {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        
        // 🔥🔥 هام جداً: يمنع Dart من فك الضغط وحذف هيدر Content-Length
        // هذا يحل مشكلة طلب النطاقات الخاطئة (15MB+)
        client.autoUncompress = false; 
        
        final proxyRequest = await client.getUrl(Uri.parse(onlineUrl!));

        // نسخ الهيدرز
        onlineHeaders?.forEach((k, v) => proxyRequest.headers.set(k, v));
        
        // تمرير الـ Range كما هو (أو تحويله إذا كان السيرفر يحتاج ذلك)
        // في حالتك، يبدو أن السيرفر يقبل Range أو X-Alt-Range، سنمرر Range القياسي هنا لضمان التوافق
        if (request.headers.value(HttpHeaders.rangeHeader) != null) {
          final rangeVal = request.headers.value(HttpHeaders.rangeHeader)!;
          proxyRequest.headers.set(HttpHeaders.rangeHeader, rangeVal);
          // FirebaseCrashlytics.instance.log("🌐 Online Range: $rangeVal");
        }

        final proxyResponse = await proxyRequest.close();

        // نسخ الحالة (206 Partial Content هو المطلوب للبث)
        request.response.statusCode = proxyResponse.statusCode;
        
        // نسخ الهيدرز المهمة (Content-Range, Content-Length, Content-Type)
        proxyResponse.headers.forEach((name, values) {
            request.response.headers.set(name, values);
        });
        
        // التأكد من تمرير الطول إذا لم يتم نسخه تلقائياً
        if (proxyResponse.contentLength != -1) {
            request.response.contentLength = proxyResponse.contentLength;
        }

        await request.response.addStream(proxyResponse);
        await request.response.close();
        return;
      }

      // =========================================================
      // 📂 2. أوفلاين (القراءة من الملف المشفر محلياً)
      // =========================================================
      final response = request.response;
      final file = File(encryptedFilePath!);
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final encryptedLen = await file.length();
      final int fullBlocks = encryptedLen ~/ encryptedBlockSize;
      final int remainingBytes = encryptedLen % encryptedBlockSize;
      final int lastBlockSize = remainingBytes > (ivLength + tagLength) 
          ? (remainingBytes - ivLength - tagLength) : 0;
      final int originalSize = (fullBlocks * plainBlockSize) + lastBlockSize;

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, 'application/pdf');

      int start = 0;
      int end = originalSize - 1;
      String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      if (rangeHeader != null) {
        try {
          final range = rangeHeader.split('=')[1].split('-');
          start = int.parse(range[0]);
          if (range.length > 1 && range[1].isNotEmpty) end = int.parse(range[1]);
          if (end >= originalSize) end = originalSize - 1;
          
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$originalSize');
        } catch (_) {
           response.statusCode = HttpStatus.ok;
        }
      } else {
        response.statusCode = HttpStatus.ok;
      }

      response.contentLength = end - start + 1;

      if (request.method != 'HEAD') {
        final streamResponsePort = ReceivePort();
        _workerSendPort!.send(_DecryptRequest(
          filePath: encryptedFilePath!,
          keyBase64: keyBase64!,
          startByte: start,
          endByte: end,
          replyPort: streamResponsePort.sendPort,
        ));
        await for (final chunk in streamResponsePort) {
          if (chunk is Uint8List) response.add(chunk);
          else if (chunk == null) break;
        }
        streamResponsePort.close();
      }
      await response.close();

    } catch (e) {
      try { await request.response.close(); } catch (_) {}
    }
  }

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

      int startBlockIndex = req.startByte ~/ plainBlockSize;
      int endBlockIndex = req.endByte ~/ plainBlockSize;
      int offsetInFirstBlock = req.startByte % plainBlockSize;
      
      int bytesSent = 0;
      int totalBytesToSend = req.endByte - req.startByte + 1;

      for (int i = startBlockIndex; i <= endBlockIndex; i++) {
        if (bytesSent >= totalBytesToSend) break;
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

          int chunkStart = (i == startBlockIndex) ? offsetInFirstBlock : 0;
          int chunkEnd = decryptedBlock.length;
          if (chunkEnd - chunkStart > (totalBytesToSend - bytesSent)) {
            chunkEnd = chunkStart + (totalBytesToSend - bytesSent);
          }
          if (chunkStart < chunkEnd) {
            req.replyPort.send(Uint8List.fromList(decryptedBlock.sublist(chunkStart, chunkEnd)));
            bytesSent += (chunkEnd - chunkStart);
          }
        } catch (_) {}
      }
    } catch (_) {} finally {
      await raf?.close();
      req.replyPort.send(null);
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
