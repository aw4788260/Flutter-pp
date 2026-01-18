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
      // ✅ التعديل 1: الربط بـ anyIPv4 (0.0.0.0) بدلاً من loopbackIPv4
      // هذا يجعله مرئياً لكل مكونات النظام بما فيها ExoPlayer بشكل مؤكد
      _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port, shared: true);
      
      _server?.autoCompress = false; 
      // إيقاف الـ idle timeout لمنع إغلاق الاتصال أثناء التوقف المؤقت للفيديو
      _server?.idleTimeout = null; 
      
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

      // ✅ التعديل 2: فك ترميز المسار بعناية لدعم المسافات والرموز
      final decodedPath = Uri.decodeComponent(pathParam);
      final file = File(decodedPath);
      
      if (!await file.exists()) {
        FirebaseCrashlytics.instance.log('❌ Proxy: File missing at $decodedPath');
        return Response.notFound('File not found');
      }

      String contentType = 'application/octet-stream'; 
      if (decodedPath.toLowerCase().contains('.pdf')) {
         contentType = 'application/pdf';
      } 

      final encryptedLength = await file.length();
      final int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;
      final int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      final int overhead = encChunkSize - plainChunkSize; 

      final int totalChunks = (encryptedLength / encChunkSize).ceil();
      if (totalChunks == 0) return Response.ok('');

      final int originalFileSize = ((totalChunks - 1) * plainChunkSize) + max(0, (encryptedLength - ((totalChunks - 1) * encChunkSize)) - overhead);

      // معالجة الـ Range Header
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

      if (request.method == 'HEAD') {
        return Response.ok(null, headers: {
            'Content-Type': contentType,
            'Content-Length': originalFileSize.toString(),
            'Accept-Ranges': 'bytes',
        });
      }

      // ✅ التعديل 3: إضافة هيدر Connection: close لمنع تعليق المشغل
      return Response(
        206, 
        body: _createDecryptedStream(file, start, end),
        headers: {
          'Content-Type': contentType, 
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$originalFileSize',
          'Accept-Ranges': 'bytes',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache',
        },
      );

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Request Handler Error');
      return Response.internalServerError(body: 'Proxy Error');
    }
  }

  Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd) async* {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      
      // ثوابت التشفير
      const int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      const int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;

      int startChunkIndex = reqStart ~/ plainChunkSize;
      int endChunkIndex = reqEnd ~/ plainChunkSize;
      final fileLen = await file.length();

      for (int i = startChunkIndex; i <= endChunkIndex; i++) {
        int seekPos = i * encChunkSize;
        if (seekPos >= fileLen) break;

        await raf.setPosition(seekPos);
        int bytesToRead = min(encChunkSize, fileLen - seekPos);

        // ✅ حماية من قراءة 0 بايت
        if (bytesToRead <= EncryptionHelper.IV_LENGTH) break;

        Uint8List encryptedBlock = await raf.read(bytesToRead);
        
        try {
          Uint8List decryptedBlock = EncryptionHelper.decryptBlock(encryptedBlock);

          int blockStartInPlain = i * plainChunkSize;
          int sliceStart = max(0, reqStart - blockStartInPlain);
          int sliceEnd = min(decryptedBlock.length, reqEnd - blockStartInPlain + 1);

          if (sliceStart < sliceEnd) {
            yield decryptedBlock.sublist(sliceStart, sliceEnd);
          }
        } catch (e) {
           print("Decryption Skip at chunk $i: $e");
           continue; 
        }
      }
    } catch(e) {
       print("Stream Error: $e");
    } finally {
      await raf?.close();
    }
  }
}
