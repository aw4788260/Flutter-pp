import 'dart:io';
import 'dart:async';
import 'dart:isolate'; 
import 'dart:math';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:encrypt/encrypt.dart' as encrypt; 
import '../utils/encryption_helper.dart';

class LocalProxyService {
  static final LocalProxyService _instance = LocalProxyService._internal();
  
  factory LocalProxyService() {
    return _instance;
  }
  
  LocalProxyService._internal();

  Isolate? _serverIsolate;
  final int port = 8080;
  
  ReceivePort? _receivePort;
  Completer<void>? _readyCompleter;

  Future<void> start() async {
    if (_serverIsolate != null) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        await _readyCompleter!.future;
      }
      return;
    }

    _readyCompleter = Completer<void>();

    try {
      await EncryptionHelper.init();
      String keyBase64 = EncryptionHelper.key.base64;
      
      _receivePort = ReceivePort();

      _serverIsolate = await Isolate.spawn(
        _proxyServerEntryPoint, 
        _ProxyInitData(_receivePort!.sendPort, keyBase64, port)
      );
      
      await for (final message in _receivePort!) {
        if (message == "READY") {
          print('✅ Proxy Isolate is READY and Listening on port $port');
          _readyCompleter?.complete();
          break; 
        } else if (message.toString().startsWith("ERROR")) {
          print('❌ Proxy Start Error: $message');
          _readyCompleter?.completeError(message);
          stop(); 
          break;
        }
      }
      
    } catch (e) {
      print("Proxy Launch Error: $e");
      stop();
    }
  }

  void stop() {
    _readyCompleter = null;
    if (_serverIsolate != null) {
        print('🛑 Stopping Proxy Isolate');
        _receivePort?.close();
        _serverIsolate?.kill(priority: Isolate.immediate);
        _serverIsolate = null;
    }
  }
}

class _ProxyInitData {
  final SendPort sendPort;
  final String keyBase64;
  final int port;

  _ProxyInitData(this.sendPort, this.keyBase64, this.port);
}

void _proxyServerEntryPoint(_ProxyInitData initData) async {
   try {
     final key = encrypt.Key.fromBase64(initData.keyBase64);
     final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
     
     final router = Router();
     router.get('/video', (Request req) => _handleRequest(req, encrypter));
     router.head('/video', (Request req) => _handleRequest(req, encrypter));
     
     final server = await shelf_io.serve(
       router, 
       InternetAddress.anyIPv4, 
       initData.port, 
       shared: false
     );
     
     server.autoCompress = false;
     server.idleTimeout = const Duration(seconds: 60);
     
     initData.sendPort.send("READY");
     
   } catch (e) {
     initData.sendPort.send("ERROR: $e");
   }
}

Future<Response> _handleRequest(Request request, encrypt.Encrypter encrypter) async {
  try {
    final pathParam = request.url.queryParameters['path'];
    if (pathParam == null) return Response.notFound('Path missing');

    final decodedPath = Uri.decodeComponent(pathParam);
    final file = File(decodedPath);
    
    // ✅ تسجيل وصول الطلب لتسهيل التتبع
    print("🔗 Proxy Request: ${request.method} | Type: ${decodedPath.contains('aud_') ? 'AUDIO' : 'VIDEO'}");

    if (!await file.exists()) {
      print("❌ File not found: $decodedPath");
      return Response.notFound('File not found');
    }

    // ✅ تحسين تحديد نوع المحتوى لضمان استجابة المشغل بشكل صحيح
    String contentType = 'video/mp4'; 
    if (decodedPath.contains('aud_')) {
      contentType = 'audio/mp4';
    } else if (decodedPath.toLowerCase().contains('.pdf')) {
      contentType = 'application/pdf';
    }

    final encryptedLength = await file.length();
    
    const int CHUNK_SIZE = 128 * 1024; 
    const int IV_LENGTH = 12;
    const int TAG_LENGTH = 16;
    const int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

    final int totalChunks = (encryptedLength / ENCRYPTED_CHUNK_SIZE).ceil();
    if (totalChunks == 0) return Response.ok('');

    final int plainChunkSize = CHUNK_SIZE;
    final int overhead = ENCRYPTED_CHUNK_SIZE - plainChunkSize; 
    final int originalFileSize = ((totalChunks - 1) * plainChunkSize) + max(0, (encryptedLength - ((totalChunks - 1) * ENCRYPTED_CHUNK_SIZE)) - overhead);

    final rangeHeader = request.headers['range'];
    int start = 0;
    int end = originalFileSize - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      if (parts.isNotEmpty) start = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) end = int.tryParse(parts[1]) ?? originalFileSize - 1;
    }

    if (start >= originalFileSize) {
       return Response(416, body: 'Invalid Range', headers: {'Content-Range': 'bytes */$originalFileSize'});
    }
    
    final contentLength = end - start + 1;

    final Map<String, Object> headers = {
        'Content-Type': contentType, 
        'Content-Length': contentLength.toString(),
        'Accept-Ranges': 'bytes',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Connection': 'keep-alive',
    };

    if (request.method == 'HEAD') {
      return Response.ok(null, headers: headers);
    }

    headers['Content-Range'] = 'bytes $start-$end/$originalFileSize';

    return Response(
      206, 
      body: _createDecryptedStream(file, start, end, encrypter),
      headers: headers,
    );

  } catch (e) {
    print("Proxy Request Error: $e");
    return Response.internalServerError(body: 'Proxy Error');
  }
}

Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd, encrypt.Encrypter encrypter) async* {
  RandomAccessFile? raf;
  int totalSent = 0; 
  final int requiredLength = reqEnd - reqStart + 1;

  try {
    raf = await file.open(mode: FileMode.read);
    
    const int CHUNK_SIZE = 128 * 1024;
    const int IV_LENGTH = 12;
    const int TAG_LENGTH = 16;
    const int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

    int startChunkIndex = reqStart ~/ CHUNK_SIZE;
    int endChunkIndex = reqEnd ~/ CHUNK_SIZE;
    final fileLen = await file.length();

    for (int i = startChunkIndex; i <= endChunkIndex; i++) {
      if (totalSent >= requiredLength) break;

      // ✅ التعديل الأهم: إعطاء فرصة للمعالج (Isolate) لاستقبال طلبات الصوت أثناء فك تشفير الفيديو
      // هذا يمنع "تجمد" البروكسي عند فك التشفير البرمجي الثقيل على ARMv7
      await Future.delayed(Duration.zero);

      int seekPos = i * ENCRYPTED_CHUNK_SIZE;
      if (seekPos >= fileLen) break;

      await raf.setPosition(seekPos);
      
      int bytesToRead = min(ENCRYPTED_CHUNK_SIZE, fileLen - seekPos);
      if (bytesToRead <= IV_LENGTH) break;

      Uint8List encryptedBlock = await raf.read(bytesToRead);
      Uint8List outputBlock;

      try {
        if (encryptedBlock.length < IV_LENGTH) {
             throw Exception("Invalid block size");
        }
        final iv = encrypt.IV(encryptedBlock.sublist(0, IV_LENGTH));
        final cipherBytes = encryptedBlock.sublist(IV_LENGTH);
        
        final decrypted = encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: iv);
        outputBlock = Uint8List.fromList(decrypted);

      } catch (e) {
         print("Decryption Error at chunk $i: $e");
         int expectedSize = (bytesToRead == ENCRYPTED_CHUNK_SIZE) 
             ? CHUNK_SIZE 
             : max(0, bytesToRead - IV_LENGTH - TAG_LENGTH);
         outputBlock = Uint8List(expectedSize);
      }

      if (outputBlock.isNotEmpty) {
        int blockStartInPlain = i * CHUNK_SIZE;
        int sliceStart = max(0, reqStart - blockStartInPlain);
        int sliceEnd = min(outputBlock.length, reqEnd - blockStartInPlain + 1);

        if (sliceStart < sliceEnd) {
          final dataChunk = outputBlock.sublist(sliceStart, sliceEnd);
          totalSent += dataChunk.length;
          yield dataChunk;
        }
      }
    }
  } catch(e) {
     print("Stream Error: $e");
  } finally {
    if (totalSent < requiredLength) {
        int missingBytes = requiredLength - totalSent;
        if (missingBytes < 512 * 1024) {
           yield Uint8List(missingBytes);
        }
    }
    await raf?.close();
  }
}
