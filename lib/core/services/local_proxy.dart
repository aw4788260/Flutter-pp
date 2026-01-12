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
  HttpServer? _server;
  final int port = 8080;

  /// بدء السيرفر
  Future<void> start() async {
    if (_server != null) return;

    // التأكد من تهيئة التشفير (المفاتيح)
    try {
      await EncryptionHelper.init();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Encryption Init Failed', fatal: true);
      return;
    }

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
      final encryptedLength = await file.length();
      
      // ثوابت الأحجام من EncryptionHelper
      final int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;
      final int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      final int overhead = encChunkSize - plainChunkSize; // (IV + Tag)

      // حساب عدد الكتل الكلي في الملف المشفر
      final int totalChunks = (encryptedLength / encChunkSize).ceil();
      
      // حساب الحجم الصافي (الأصلي) للملف الافتراضي
      // الحجم = (عدد الكتل الكاملة * حجم الكتلة الصافية) + (حجم آخر كتلة صافية)
      
      // حجم آخر كتلة مشفرة قد يكون أقل من الحجم الكامل
      final int lastEncChunkSize = encryptedLength - ((totalChunks - 1) * encChunkSize);
      
      // حجم آخر كتلة صافية (نطرح منها الـ overhead: IV و Tag)
      final int lastPlainChunkSize = max(0, lastEncChunkSize - overhead);
      
      // الحجم الكلي للملف "المفكوك"
      final int originalFileSize = ((totalChunks - 1) * plainChunkSize) + lastPlainChunkSize;

      // 1. معالجة طلب الـ Range من مشغل الفيديو
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

      // التأكد من الحدود الصحيحة
      if (start < 0) start = 0;
      if (end >= originalFileSize) end = originalFileSize - 1;
      
      final contentLength = end - start + 1;

      FirebaseCrashlytics.instance.log("📡 Proxy Stream: Range $start-$end / $originalFileSize (Encrypted Size: $encryptedLength)");

      // 2. إنشاء Stream يقرأ الكتل المطلوبة ويفك تشفيرها
      final stream = _createDecryptedStream(file, start, end);

      // 3. إرجاع استجابة جزئية (206 Partial Content)
      return Response(
        206,
        body: stream,
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$originalFileSize',
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

  /// دالة إنشاء تيار البيانات (The Core Logic - Chunked GCM)
  Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd) async* {
    RandomAccessFile? raf;
    
    try {
      raf = await file.open(mode: FileMode.read);
      
      // ثوابت الأحجام
      const int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      const int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;

      // تحديد رقم أول وآخر كتلة نحتاج قراءتها بناءً على الطلب (Request)
      // مثال: إذا طلب بايت رقم 100000 وحجم الكتلة 65536، إذن نحن نبدأ من الكتلة رقم 1
      int startChunkIndex = reqStart ~/ plainChunkSize;
      int endChunkIndex = reqEnd ~/ plainChunkSize;

      final fileLen = await file.length();

      for (int i = startChunkIndex; i <= endChunkIndex; i++) {
        // حساب موقع القراءة من الملف المشفر (Random Access)
        // كل كتلة مشفرة تبدأ عند مضاعفات ENCRYPTED_CHUNK_SIZE
        int seekPos = i * encChunkSize;
        
        if (seekPos >= fileLen) break; // حماية إضافية

        await raf.setPosition(seekPos);

        // قراءة الكتلة المشفرة
        // قد تكون الكتلة الأخيرة أصغر من الحجم الكامل
        int bytesToRead = encChunkSize;
        if (seekPos + bytesToRead > fileLen) {
           bytesToRead = fileLen - seekPos;
        }

        if (bytesToRead <= 0) break;

        Uint8List encryptedBlock = await raf.read(bytesToRead);
        
        // فك تشفير الكتلة بالكامل
        Uint8List decryptedBlock;
        try {
          decryptedBlock = EncryptionHelper.decryptBlock(encryptedBlock);
        } catch (e, stack) {
           FirebaseCrashlytics.instance.recordError(
             e, 
             stack, 
             reason: 'Proxy Decrypt Block Failed',
             information: ['Chunk Index: $i', 'Block Size: ${encryptedBlock.length}']
           );
           // إذا فشل فك كتلة، نوقف الستريم بدلاً من إرسال بيانات تالفة قد تسبب كراش للمشغل
           throw e; 
        }

        // حساب أي جزء من هذه الكتلة (المفكوك) نحتاج إرساله للمشغل
        // بداية هذه الكتلة في الملف "الصافي" المتخيل
        int blockStartInPlain = i * plainChunkSize;
        
        // حساب الإزاحة (Offset) داخل الكتلة المفكوكة
        // إذا كانت هذه أول كتلة مطلوبة، قد لا نبدأ من أولها (reqStart > blockStartInPlain)
        int sliceStart = max(0, reqStart - blockStartInPlain);
        
        // حساب النهاية داخل الكتلة المفكوكة
        // إذا كانت هذه آخر كتلة مطلوبة، قد لا نرسلها كاملة (reqEnd < blockEndInPlain)
        // decryptedBlock.length هو الحجم الفعلي للبيانات في هذه الكتلة
        int sliceEnd = min(decryptedBlock.length, reqEnd - blockStartInPlain + 1);

        if (sliceStart < sliceEnd) {
          yield decryptedBlock.sublist(sliceStart, sliceEnd);
        }
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
