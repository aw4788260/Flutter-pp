import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/encryption_helper.dart';

class LocalProxyService {
  static final LocalProxyService _instance = LocalProxyService._internal();
  
  factory LocalProxyService() {
    return _instance;
  }
  
  LocalProxyService._internal();

  HttpServer? _server;
  final int port = 8080;
  int _usageCount = 0;

  Future<void> start() async {
    _usageCount++; 
    
    if (_server != null) return;

    try {
      await EncryptionHelper.init();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Encryption Init Failed', fatal: true);
      return;
    }

    final router = Router();
    router.head('/video', _handleRequest);
    router.get('/video', _handleRequest);

    try {
      // ✅ التعديل الجذري 1: استخدام loopbackIPv4 بدلاً من anyIPv4
      // هذا يحل مشكلة عدم وصول الطلب على الأجهزة القديمة
      // ✅ التعديل 2: إزالة shared: true لتجنب مشاكل المنافذ المعلقة
      _server = await shelf_io.serve(
        router, 
        InternetAddress.loopbackIPv4, // (127.0.0.1)
        port, 
        shared: false 
      );

      _server?.autoCompress = false;
      // مهلة قصيرة لقتل الاتصالات الميتة فوراً
      _server?.idleTimeout = const Duration(seconds: 1);
      
      FirebaseCrashlytics.instance.log('🔒 Proxy Started on ${_server!.address.host}:${_server!.port}');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Start Failed');
    }
  }

  void stop() {
    _usageCount--; 
    if (_usageCount <= 0) {
        _usageCount = 0;
        if (_server != null) {
            FirebaseCrashlytics.instance.log('🛑 Proxy Stopped');
            _server?.close(force: true);
            _server = null;
        }
    }
  }

  Future<Response> _handleRequest(Request request) async {
    try {
      final pathParam = request.url.queryParameters['path'];
      if (pathParam == null) return Response.notFound('Path missing');

      final decodedPath = Uri.decodeComponent(pathParam);
      final file = File(decodedPath);
      
      // تسجيل وصول الطلب للتأكد من حل مشكلة الاتصال
      final bool isLikelyAudio = decodedPath.contains('aud_') || decodedPath.contains('audio');
      final String logMsg = "📡 Proxy Request: ${isLikelyAudio ? 'AUDIO' : 'VIDEO'} | Path: ${decodedPath.split('/').last} | Range: ${request.headers['range']}";
      print(logMsg);
      // FirebaseCrashlytics.instance.log(logMsg); 

      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      String contentType = 'video/mp4'; 
      if (decodedPath.toLowerCase().contains('.pdf')) contentType = 'application/pdf';

      final encryptedLength = await file.length();
      
      final int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;
      final int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      final int overhead = encChunkSize - plainChunkSize; 

      final int totalChunks = (encryptedLength / encChunkSize).ceil();
      if (totalChunks == 0) return Response.ok('');

      final int originalFileSize = ((totalChunks - 1) * plainChunkSize) + max(0, (encryptedLength - ((totalChunks - 1) * encChunkSize)) - overhead);

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

      // ✅ التعديل 3: إغلاق الاتصال فوراً (Connection: close)
      final Map<String, Object> headers = {
          'Content-Type': contentType, 
          'Content-Length': contentLength.toString(),
          'Accept-Ranges': 'bytes',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Connection': 'close', 
      };

      if (request.method == 'HEAD') {
        return Response.ok(null, headers: headers);
      }

      headers['Content-Range'] = 'bytes $start-$end/$originalFileSize';

      return Response(
        206, 
        body: _createDecryptedStream(file, start, end),
        headers: headers,
      );

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Request Handler Error');
      return Response.internalServerError(body: 'Proxy Error');
    }
  }

  Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd) async* {
    RandomAccessFile? raf;
    int totalSent = 0; 
    final int requiredLength = reqEnd - reqStart + 1;

    try {
      raf = await file.open(mode: FileMode.read);
      
      const int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      const int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;
      const int ivLen = EncryptionHelper.IV_LENGTH;
      const int tagLen = EncryptionHelper.TAG_LENGTH;

      int startChunkIndex = reqStart ~/ plainChunkSize;
      int endChunkIndex = reqEnd ~/ plainChunkSize;
      final fileLen = await file.length();

      for (int i = startChunkIndex; i <= endChunkIndex; i++) {
        if (totalSent >= requiredLength) break;

        int seekPos = i * encChunkSize;
        if (seekPos >= fileLen) break;

        await raf.setPosition(seekPos);
        
        int bytesToRead = min(encChunkSize, fileLen - seekPos);
        if (bytesToRead <= ivLen) break;

        Uint8List encryptedBlock = await raf.read(bytesToRead);
        Uint8List outputBlock;

        try {
          outputBlock = EncryptionHelper.decryptBlock(encryptedBlock);
        } catch (e) {
           print("❌ Decryption ERROR at chunk $i: $e");
           // إرسال أصفار في حالة الخطأ البسيط
           int expectedSize = (bytesToRead == encChunkSize) 
               ? plainChunkSize 
               : max(0, bytesToRead - ivLen - tagLen);
           outputBlock = Uint8List(expectedSize);
        }

        if (outputBlock.isNotEmpty) {
          int blockStartInPlain = i * plainChunkSize;
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
       print("Stream Interrupted: $e");
    } finally {
      // ✅ التعديل 4: المنطق الذكي للفجوات (Smart Gap Handling)
      if (totalSent < requiredLength) {
          int missingBytes = requiredLength - totalSent;
          
          if (missingBytes < 512 * 1024) {
             print("⚠️ Small Gap ($missingBytes bytes): Filling with zeros.");
             yield Uint8List(missingBytes);
          } else {
             // إغلاق الاتصال للفجوات الكبيرة لإجبار المشغل على إعادة الطلب
             print("🛑 Large Gap ($missingBytes bytes): Closing connection.");
          }
      }
      await raf?.close();
    }
  }
}
