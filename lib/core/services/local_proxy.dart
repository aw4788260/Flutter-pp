import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/encryption_helper.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class LocalProxyService {
  HttpServer? _server;
  final int port = 8080;

  /// بدء السيرفر
  Future<void> start() async {
    if (_server != null) return;

    final router = Router();
    router.get('/video', _handleVideoRequest);

    try {
      _server = await shelf_io.serve(router, InternetAddress.loopbackIPv4, port);
      FirebaseCrashlytics.instance.log('🔒 Proxy Started on port ${_server!.port}');
      print('🔒 Local Proxy running on port ${_server!.port}');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Start Failed', fatal: true);
    }
  }

  /// معالجة طلب الفيديو (Stream Response)
  Future<Response> _handleVideoRequest(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null) {
      return Response.notFound('Path not provided');
    }

    final file = File(path);
    if (!await file.exists()) {
      FirebaseCrashlytics.instance.log("⚠️ Proxy: File not found at $path");
      return Response.notFound('File not found');
    }

    try {
      final fileLength = await file.length();
      
      // 1. معالجة طلب الـ Range
      final rangeHeader = request.headers['range'];
      int start = 0;
      int end = fileLength - 1;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        if (parts.isNotEmpty) {
          start = int.tryParse(parts[0]) ?? 0;
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? fileLength - 1;
        }
      }

      // التأكد من الحدود الصحيحة
      if (start < 0) start = 0;
      if (end >= fileLength) end = fileLength - 1;
      
      final contentLength = end - start + 1;

      FirebaseCrashlytics.instance.log("📡 Proxy Stream: Range $start-$end / $fileLength");

      // 2. إنشاء Stream يقرأ ويفك التشفير فورياً
      final stream = _createDecryptedStream(file, start, end, fileLength);

      // 3. إرجاع استجابة جزئية (206 Partial Content)
      return Response(
        206,
        body: stream,
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$fileLength',
          'Accept-Ranges': 'bytes',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-store',
        },
      );

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Request Error');
      return Response.internalServerError(body: 'Internal Error: $e');
    }
  }

  /// دالة إنشاء تيار البيانات (The Core Logic)
  Stream<List<int>> _createDecryptedStream(File file, int start, int end, int fileLength) async* {
    RandomAccessFile? raf;
    
    try {
      raf = await file.open(mode: FileMode.read);
      const int blockSize = 16;
      
      // ✅ تحديد بداية البلوك (Aligned Start)
      final int alignedStart = (start ~/ blockSize) * blockSize;
      final int offsetInBlock = start - alignedStart;
      
      // ✅ تحديد الـ IV المناسب للبلوك المطلوب
      encrypt.IV currentIV;
      if (alignedStart == 0) {
        currentIV = EncryptionHelper.iv; 
        await raf.setPosition(0);
      } else {
        // نأخذ الـ 16 بايت المشفرة السابقة كـ IV للبلوك الحالي
        await raf.setPosition(alignedStart - blockSize);
        final ivBytes = await raf.read(blockSize);
        currentIV = encrypt.IV(Uint8List.fromList(ivBytes));
      }

      // ✅ إعداد مفك التشفير بدون Padding (نحن نتحكم به يدوياً)
      final key = EncryptionHelper.key; 
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: null));

      int currentPos = alignedStart;
      const int bufferSize = 64 * 1024; // 64KB

      while (currentPos <= end) {
        int bytesToRead = bufferSize;
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }
        
        // المحاذاة مع البلوكات (16 بايت)
        if (bytesToRead % blockSize != 0 && (currentPos + bytesToRead) < fileLength) {
           bytesToRead = ((bytesToRead ~/ blockSize) + 1) * blockSize;
        }

        if (bytesToRead <= 0) break;

        final encryptedChunk = await raf.read(bytesToRead);
        if (encryptedChunk.isEmpty) break;

        // فك التشفير
        final decryptedChunk = encrypter.decryptBytes(
          encrypt.Encrypted(encryptedChunk), 
          iv: currentIV
        );

        // تحديث الـ IV للدورة القادمة
        if (encryptedChunk.length >= blockSize) {
           currentIV = encrypt.IV(encryptedChunk.sublist(encryptedChunk.length - blockSize));
        }

        List<int> result = decryptedChunk;

        // ✅ معالجة الـ Padding في آخر بلوك بالملف
        if (currentPos + encryptedChunk.length >= fileLength) {
          int lastByte = result.last;
          if (lastByte > 0 && lastByte <= 16) {
            // التحقق إذا كان هذا فعلاً حشو PKCS7
            bool isPadding = true;
            for (int i = 1; i <= lastByte; i++) {
              if (result[result.length - i] != lastByte) {
                isPadding = false;
                break;
              }
            }
            if (isPadding) {
              result = result.sublist(0, result.length - lastByte);
            }
          }
        }

        // قص الزيادات الناتجة عن المحاذاة (Alignment) في البداية والنهاية
        if (currentPos == alignedStart && offsetInBlock > 0) {
          result = result.length > offsetInBlock ? result.sublist(offsetInBlock) : [];
        }

        // حساب الكمية المتبقية المطلوب إرسالها فعلياً بناءً على طلب الـ Range
        final int sentSoFar = (currentPos > alignedStart) ? (currentPos - start) : 0;
        final int remainingToSent = (end - start + 1) - sentSoFar;

        if (result.length > remainingToSent) {
          result = result.sublist(0, remainingToSent);
        }

        if (result.isNotEmpty) {
          yield result;
        }

        currentPos += encryptedChunk.length;
        if (currentPos > end) break;
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: '🚨 Proxy Stream Loop Error');
    } finally {
      await raf?.close();
    }
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
    FirebaseCrashlytics.instance.log('🛑 Proxy Stopped');
  }
}
