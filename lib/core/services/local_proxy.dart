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
    
    if (_server != null) {
        return;
    }

    try {
      FirebaseCrashlytics.instance.log('🔒 Proxy: Initializing Encryption...');
      await EncryptionHelper.init();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Encryption Init Failed', fatal: true);
      return;
    }

    final router = Router();
    // ✅ دعم طلبات HEAD و GET (ضروري للمشغلات)
    router.head('/video', _handleRequest);
    router.get('/video', _handleRequest);

    try {
      _server = await shelf_io.serve(router, InternetAddress.loopbackIPv4, port);
      // تسريع الاستجابة للطلبات المحلية
      _server?.autoCompress = false; 
      FirebaseCrashlytics.instance.log('🔒 Proxy Started on port ${_server!.port}');
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
    final path = request.url.queryParameters['path'];
    
    // تسجيل تفاصيل الطلب
    FirebaseCrashlytics.instance.log('📥 Proxy Request: ${request.method} $path');

    if (path == null) {
      return Response.notFound('Path not provided');
    }

    final decodedPath = Uri.decodeComponent(path);
    final file = File(decodedPath);
    
    if (!await file.exists()) {
      FirebaseCrashlytics.instance.log('❌ Proxy File Not Found: $decodedPath');
      return Response.notFound('File not found');
    }

    // ✅ التعديل الجوهري: استخدام octet-stream
    // هذا يجبر المشغل على فحص محتوى الملف (Sniffing) لمعرفة نوعه (MP4, WebM, AAC)
    // بدلاً من الاعتماد على الهيدر الذي قد يكون خاطئاً.
    String contentType = 'application/octet-stream'; 
    
    if (decodedPath.toLowerCase().contains('.pdf')) {
       contentType = 'application/pdf';
    } 

    try {
      final encryptedLength = await file.length();
      
      final int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;
      final int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      final int overhead = encChunkSize - plainChunkSize; 

      final int totalChunks = (encryptedLength / encChunkSize).ceil();
      // حماية من الملفات الفارغة أو التالفة
      if (totalChunks == 0) {
         return Response.ok('');
      }

      final int lastEncChunkSize = encryptedLength - ((totalChunks - 1) * encChunkSize);
      final int lastPlainChunkSize = max(0, lastEncChunkSize - overhead);
      final int originalFileSize = ((totalChunks - 1) * plainChunkSize) + lastPlainChunkSize;

      final rangeHeader = request.headers['range'];
      int start = 0;
      int end = originalFileSize - 1;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        if (parts.isNotEmpty) {
          start = int.tryParse(parts[0]) ?? 0;
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? originalFileSize - 1;
        }
      }

      // تصحيح النطاق
      if (start >= originalFileSize) {
         return Response(416, body: 'Requested Range Not Satisfiable', headers: {'Content-Range': 'bytes */$originalFileSize'});
      }
      if (end >= originalFileSize) end = originalFileSize - 1;
      
      final contentLength = end - start + 1;

      // تسجيل نطاق البث
      FirebaseCrashlytics.instance.log('Range Request: $start-$end / $originalFileSize (Type: $contentType)');

      // ✅ الرد على طلب HEAD فقط بالمعلومات (بدون داتا)
      if (request.method == 'HEAD') {
        return Response.ok(
          null, 
          headers: {
            'Content-Type': contentType,
            'Content-Length': originalFileSize.toString(),
            'Accept-Ranges': 'bytes',
          }
        );
      }

      final stream = _createDecryptedStream(file, start, end);

      return Response(
        206, 
        body: stream,
        headers: {
          'Content-Type': contentType, 
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$originalFileSize',
          'Accept-Ranges': 'bytes',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache, no-store, must-revalidate', // منع الكاش
        },
      );

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Request Handling Error');
      return Response.internalServerError(body: 'Internal Error: $e');
    }
  }

  Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd) async* {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      
      const int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      const int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;

      int startChunkIndex = reqStart ~/ plainChunkSize;
      int endChunkIndex = reqEnd ~/ plainChunkSize;

      final fileLen = await file.length();

      for (int i = startChunkIndex; i <= endChunkIndex; i++) {
        int seekPos = i * encChunkSize;
        if (seekPos >= fileLen) break;

        await raf.setPosition(seekPos);

        int bytesToRead = encChunkSize;
        if (seekPos + bytesToRead > fileLen) {
           bytesToRead = fileLen - seekPos;
        }

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
           // تسجيل خطأ فك التشفير مع رقم القطعة (Chunk)
           FirebaseCrashlytics.instance.log("🚨 Decryption Error at Chunk Index: $i");
           print("Decryption error at chunk $i: $e");
           throw e; 
        }
      }
    } catch (e, s) {
       FirebaseCrashlytics.instance.recordError(e, s, reason: 'Stream Generation Error');
    } finally {
      await raf?.close();
    }
  }
}
