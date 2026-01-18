// lib/core/services/local_proxy.dart
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
      await EncryptionHelper.init();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Encryption Init Failed', fatal: true);
      return;
    }

    final router = Router();
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
            _server?.close(force: true);
            _server = null;
        }
    }
  }

  Future<Response> _handleRequest(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null) {
      return Response.notFound('Path not provided');
    }

    final decodedPath = Uri.decodeComponent(path);
    final file = File(decodedPath);
    
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    // ✅ التعديل الجوهري هنا:
    // استخدام generic types للمساعدة في اكتشاف المشغل للصيغة الصحيحة
    String contentType = 'video/mp4'; 
    
    if (decodedPath.toLowerCase().contains('.pdf')) {
       contentType = 'application/pdf';
    } else if (decodedPath.contains('aud_')) {
       // 🔴 التصحيح: لا تجبره على audio/mp4 لأن الملف قد يكون WebM
       // استخدام application/octet-stream يجبر المشغل على قراءة الهيدر الحقيقي للملف
       contentType = 'application/octet-stream'; 
    }

    try {
      final encryptedLength = await file.length();
      
      final int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;
      final int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      final int overhead = encChunkSize - plainChunkSize; 

      final int totalChunks = (encryptedLength / encChunkSize).ceil();
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

      if (start < 0) start = 0;
      if (end >= originalFileSize) end = originalFileSize - 1;
      
      final contentLength = end - start + 1;

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
          'Cache-Control': 'no-cache', // ✅ منع الكاش لضمان القراءة المباشرة
        },
      );

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Request Error');
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
          // ✅ عملية فك التشفير تتم هنا
          // ملاحظة: بما أن هذه العملية ثقيلة، إذا واجهت تقطيعاً في الصوت، 
          // قد نحتاج مستقبلاً لنقلها لـ Isolate منفصل، لكن الحل الحالي بتصحيح الـ Content-Type غالباً سيفي بالغرض.
          Uint8List decryptedBlock = EncryptionHelper.decryptBlock(encryptedBlock);

          int blockStartInPlain = i * plainChunkSize;
          int sliceStart = max(0, reqStart - blockStartInPlain);
          int sliceEnd = min(decryptedBlock.length, reqEnd - blockStartInPlain + 1);

          if (sliceStart < sliceEnd) {
            yield decryptedBlock.sublist(sliceStart, sliceEnd);
          }
        } catch (e) {
           print("Decryption error at chunk $i: $e");
           throw e; 
        }
      }
    } finally {
      await raf?.close();
    }
  }
}
