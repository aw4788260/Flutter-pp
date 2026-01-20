import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/encryption_helper.dart';

class LocalPdfServer {
  HttpServer? _server;
  final String encryptedFilePath;
  final String keyBase64;
  
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;

  static const int plainBlockSize = 32 * 1024; 
  static const int ivLength = 12;
  static const int tagLength = 16;
  static const int encryptedBlockSize = ivLength + plainBlockSize + tagLength;

  LocalPdfServer(this.encryptedFilePath, this.keyBase64);

  void _log(String message) {
    final msg = "🔍 [PDF_SERVER] $message";
    print(msg);
    try {
      FirebaseCrashlytics.instance.log(msg);
    } catch (e) { /* ignore */ }
  }

  Future<int> start() async {
    _log("Starting Server for file: $encryptedFilePath");
    
    try {
      final file = File(encryptedFilePath);
      if (!await file.exists()) {
        _log("❌ ERROR: File does not exist at path!");
        throw Exception("File not found");
      }
      
      // تهيئة المعالج
      final initPort = ReceivePort();
      _workerIsolate = await Isolate.spawn(_decryptWorkerEntry, initPort.sendPort);
      _workerSendPort = await initPort.first as SendPort;

      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_handleHttpRequest);
      
      _log("🚀 Server listening on port: ${_server!.port}");
      return _server!.port;

    } catch (e, stack) {
      _log("❌ FATAL START ERROR: $e");
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'LocalServer Start Failed');
      rethrow;
    }
  }

  Future<void> stop() async {
    _log("🛑 Stopping Server...");
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    await _server?.close(force: true);
    _server = null;
  }

  void _handleHttpRequest(HttpRequest request) async {
    final response = request.response;
    // _log("📥 Request: ${request.method} ${request.uri}");

    try {
      final file = File(encryptedFilePath);
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final encryptedLen = await file.length();

      // ✅ [تصحيح] حساب الحجم الدقيق لتجنب خطأ Content-Length
      final int fullBlocks = encryptedLen ~/ encryptedBlockSize;
      final int remainingBytes = encryptedLen % encryptedBlockSize;
      final int lastBlockSize = remainingBytes > 0 ? (remainingBytes - ivLength - tagLength) : 0;
      final int originalSize = (fullBlocks * plainBlockSize) + lastBlockSize;

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, 'application/pdf');

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
        final streamResponsePort = ReceivePort();
        
        _workerSendPort!.send(_DecryptRequest(
          filePath: encryptedFilePath,
          keyBase64: keyBase64,
          startByte: start,
          endByte: end,
          replyPort: streamResponsePort.sendPort,
        ));

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
      _log("❌ Request Handler Error: $e");
      // تجاهل الأخطاء الناتجة عن إغلاق العميل للاتصال مبكراً
      if (!e.toString().contains("Connection closed")) {
         FirebaseCrashlytics.instance.recordError(e, s, reason: 'LocalServer Request Failed');
      }
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

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
          final iv = encrypt.IV(encryptedChunk.sublist(0, ivLength));
          final cipherText = encryptedChunk.sublist(ivLength);
          
          List<int> decryptedBlock = encrypter.decryptBytes(
            encrypt.Encrypted(cipherText), 
            iv: iv
          );

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
          print("Worker Decrypt Error (Block $i): $e");
        }
      }
    } catch (e) {
      print("Worker Fatal Error: $e");
    } finally {
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

  _DecryptRequest({
    required this.filePath,
    required this.keyBase64,
    required this.startByte,
    required this.endByte,
    required this.replyPort,
  });
}
