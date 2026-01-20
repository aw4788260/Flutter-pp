import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// تأكد من المسار الصحيح
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

  // 🔍 دالة تسجيل موحدة للكونسول وفايربيس
  void _log(String message) {
    final msg = "🔍 [PDF_SERVER] $message";
    print(msg); // يظهر في الـ Run Console
    try {
      FirebaseCrashlytics.instance.log(msg); // يظهر في Firebase
    } catch (e) { /* ignore if firebase not ready */ }
  }

  Future<int> start() async {
    _log("Starting Server for file: $encryptedFilePath");
    
    try {
      final file = File(encryptedFilePath);
      if (!await file.exists()) {
        _log("❌ ERROR: File does not exist at path!");
        throw Exception("File not found");
      }
      _log("✅ File found. Size: ${await file.length()} bytes");

      final initPort = ReceivePort();
      _workerIsolate = await Isolate.spawn(_decryptWorkerEntry, initPort.sendPort);
      _workerSendPort = await initPort.first as SendPort;
      _log("✅ Worker Isolate Spawned");

      // استخدام Loopback IP
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
    _log("📥 Request: ${request.method} ${request.uri}");
    _log("Headers: Range=${request.headers.value(HttpHeaders.rangeHeader)}");

    try {
      final file = File(encryptedFilePath);
      if (!await file.exists()) {
        _log("❌ Request Error: File vanished");
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final encryptedLen = await file.length();
      final originalSize = (encryptedLen / encryptedBlockSize * plainBlockSize).toInt();

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
        _log("⚡ Serving Partial: $start - $end");
      } else {
        _log("⚡ Serving Full Content");
        response.statusCode = HttpStatus.ok;
      }

      response.contentLength = end - start + 1;

      if (request.method != 'HEAD') {
        final streamResponsePort = ReceivePort();
        
        _log("🔄 Asking Worker for bytes...");
        _workerSendPort!.send(_DecryptRequest(
          filePath: encryptedFilePath,
          keyBase64: keyBase64,
          startByte: start,
          endByte: end,
          replyPort: streamResponsePort.sendPort,
        ));

        int chunksReceived = 0;
        await for (final chunk in streamResponsePort) {
          if (chunk is Uint8List) {
            response.add(chunk);
            chunksReceived++;
          } else if (chunk == null) {
            break; 
          }
        }
        _log("✅ Stream Finished. Chunks sent: $chunksReceived");
        streamResponsePort.close();
      }
      
      await response.close();

    } catch (e, s) {
      _log("❌ Request Handler Error: $e");
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'LocalServer Request Failed');
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
    // ملاحظة: لا يمكننا استخدام Firebase داخل العزل بسهولة، سنعتمد على try-catch صارم
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
