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
      // استخدام shared: true مهم جداً لدعم الصوت والفيديو معاً
      _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port, shared: true);
      _server?.autoCompress = false;
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

      final decodedPath = Uri.decodeComponent(pathParam);
      final file = File(decodedPath);
      
      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      String contentType = 'application/octet-stream'; 
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

      if (request.method == 'HEAD') {
        return Response.ok(null, headers: {
            'Content-Type': contentType,
            'Content-Length': originalFileSize.toString(),
            'Accept-Ranges': 'bytes',
        });
      }

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
          'Connection': 'keep-alive',
        },
      );

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Request Handler Error');
      return Response.internalServerError(body: 'Proxy Error');
    }
  }

  // ✅✅ التعديل الجوهري هنا في هذه الدالة
  Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd) async* {
    RandomAccessFile? raf;
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
        int seekPos = i * encChunkSize;
        if (seekPos >= fileLen) break;

        await raf.setPosition(seekPos);
        
        int bytesToRead = min(encChunkSize, fileLen - seekPos);
        
        // إذا كان المتبقي أصغر من حجم الـ IV، فهذا ملف تالف جداً
        if (bytesToRead <= ivLen) break;

        Uint8List encryptedBlock = await raf.read(bytesToRead);
        
        Uint8List outputBlock;
        bool isCorrupted = false;

        try {
          // محاولة فك التشفير الطبيعية
          outputBlock = EncryptionHelper.decryptBlock(encryptedBlock);
        } catch (e) {
           isCorrupted = true;
           // ✅ الإصلاح: بدلاً من تجاهل الخطأ، نقوم بتوليد "صمت" أو "بيانات فارغة"
           // حساب الحجم المتوقع للنص الأصلي لهذه الكتلة
           int expectedSize = 0;
           if (bytesToRead == encChunkSize) {
             expectedSize = plainChunkSize; // كتلة كاملة
           } else {
             expectedSize = max(0, bytesToRead - ivLen - tagLen); // آخر كتلة
           }
           
           print("⚠️ Corruption at chunk $i. Replacing with $expectedSize zero bytes. Error: $e");
           
           // إنشاء بيانات فارغة (أصفار) للحفاظ على تدفق البيانات وعدم كسر الـ Content-Length
           outputBlock = Uint8List(expectedSize);
        }

        // إرسال البيانات (سواء كانت مفكوكة بنجاح أو أصفار تعويضية)
        if (outputBlock.isNotEmpty) {
          int blockStartInPlain = i * plainChunkSize;
          int sliceStart = max(0, reqStart - blockStartInPlain);
          int sliceEnd = min(outputBlock.length, reqEnd - blockStartInPlain + 1);

          if (sliceStart < sliceEnd) {
            yield outputBlock.sublist(sliceStart, sliceEnd);
          }
        }
      }
    } catch(e, s) {
       print("Stream Critical Error: $e");
       FirebaseCrashlytics.instance.recordError(e, s, reason: 'Stream Critical Error');
    } finally {
      await raf?.close();
    }
  }
}
