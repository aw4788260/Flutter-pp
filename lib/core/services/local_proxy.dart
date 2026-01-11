import 'dart:io';
import 'dart:async';
import 'dart:typed_data'; // ✅ تمت إضافة هذا السطر لحل مشكلة Uint8List
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
      FirebaseCrashlytics.instance.log("⚠️ Proxy: Missing path parameter");
      return Response.notFound('Path not provided');
    }

    final file = File(path);
    if (!await file.exists()) {
      FirebaseCrashlytics.instance.log("⚠️ Proxy: File not found at $path");
      return Response.notFound('File not found');
    }

    try {
      final fileLength = await file.length();
      
      // 1. معالجة طلب الـ Range (مهم جداً للتقديم والتأخير في الفيديو)
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
      
      // طول المحتوى المطلوب
      final contentLength = end - start + 1;

      // تسجيل الطلب للمتابعة
      FirebaseCrashlytics.instance.log("📡 Streaming request: Range $start-$end (Total: $fileLength)");

      // 2. إنشاء Stream يقرأ ويفك التشفير فورياً
      final stream = _createDecryptedStream(file, start, end, fileLength);

      // 3. إرجاع استجابة جزئية (206 Partial Content)
      return Response(
        206, // HTTP 206 Partial Content
        body: stream,
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$fileLength',
          'Accept-Ranges': 'bytes',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-store', // منع التخزين المؤقت للأمان
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
      
      // إعدادات التشفير (AES-CBC Block Size = 16)
      const int blockSize = 16;
      
      // ✅ 1. تحديد بداية القراءة (يجب أن تكون مضاعفات 16)
      // نحتاج للبدء من بداية البلوك للحصول على IV صحيح، حتى لو طلب اللاعب بايتات من منتصف البلوك
      final int alignedStart = (start ~/ blockSize) * blockSize;
      final int offsetInBlock = start - alignedStart; // الفرق الذي سنحذفه لاحقاً
      
      // ✅ 2. تحديد الـ IV (Vector) المناسب
      // في AES-CBC: الـ IV للبلوك الحالي هو النص المشفر (Ciphertext) للبلوك السابق.
      encrypt.IV currentIV;
      
      if (alignedStart == 0) {
        // إذا كنا في البداية، نستخدم الـ IV الأصلي
        currentIV = EncryptionHelper.iv; 
        await raf.setPosition(0);
      } else {
        // إذا كنا في الوسط، نقرأ الـ 16 بايت السابقة لتكون هي الـ IV
        await raf.setPosition(alignedStart - blockSize);
        final ivBytes = await raf.read(blockSize);
        currentIV = encrypt.IV(internet8ListFromList(ivBytes));
      }

      // ✅ 3. إعداد مفك التشفير (بدون Padding)
      // نستخدم padding: null لأننا سنفك أجزاء عشوائية، والحشو موجود فقط في آخر الملف
      
      // ✅ تصحيح: استخدام EncryptionHelper.key مباشرة بدلاً من محاولة استخراجه من الـ algo
      final key = EncryptionHelper.key; 
      
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: null));

      int currentPos = alignedStart;
      const int bufferSize = 64 * 1024; // قراءة 64KB في كل دفعة

      while (currentPos <= end) {
        // حساب كمية القراءة (يجب أن تكون مضاعفات 16)
        int bytesToRead = bufferSize;
        
        // تعديل الكمية لعدم تجاوز نهاية الملف
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }
        
        // التأكد من أن القراءة تتماشى مع البلوكات (إلا في آخر جزء)
        if (bytesToRead % blockSize != 0 && (currentPos + bytesToRead) < fileLength) {
           bytesToRead = ((bytesToRead ~/ blockSize) + 1) * blockSize;
        }

        if (bytesToRead == 0) break;

        // قراءة البيانات المشفرة
        final encryptedChunk = await raf.read(bytesToRead);
        if (encryptedChunk.isEmpty) break;

        // فك التشفير
        final decryptedChunk = encrypter.decryptBytes(
          encrypt.Encrypted(encryptedChunk), 
          iv: currentIV
        );

        // تحديث الـ IV للدورة القادمة (آخر 16 بايت من المشفر تصبح الـ IV القادم)
        if (encryptedChunk.length >= blockSize) {
           currentIV = encrypt.IV(encryptedChunk.sublist(encryptedChunk.length - blockSize));
        }

        // ✅ 4. معالجة البيانات وإرسالها
        List<int> result = decryptedChunk;

        // إذا كانت هذه أول دفعة، نحذف البايتات الزائدة من البداية (offsetInBlock)
        if (currentPos == alignedStart && offsetInBlock > 0) {
          if (result.length > offsetInBlock) {
             result = result.sublist(offsetInBlock);
          } else {
             result = [];
          }
        }

        // إذا تجاوزنا النهاية المطلوبة، نقص الزائد
        final int bytesLeftToSend = (end - (currentPos + (currentPos == alignedStart ? offsetInBlock : 0))) + 1;
        if (result.length > bytesLeftToSend) {
          result = result.sublist(0, bytesLeftToSend);
        }

        if (result.isNotEmpty) {
          yield result;
        }

        currentPos += encryptedChunk.length;
        
        // الخروج إذا وصلنا للنهاية
        if (currentPos > end) break;
      }

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Streaming Loop Error');
      // لا نعيد الخطأ للمشغل لكي لا يقطع، بل ننهي البث فقط
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// دالة مساعدة لتحويل القوائم
  Uint8List internet8ListFromList(List<int> data) {
    if (data is Uint8List) return data;
    return Uint8List.fromList(data);
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
  }
}
