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
    
    // إذا كان السيرفر يعمل بالفعل، لا داعي لإعادة تشغيله
    if (_server != null) return;

    try {
      // التأكد من تهيئة مفاتيح التشفير
      await EncryptionHelper.init();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Encryption Init Failed', fatal: true);
      return;
    }

    final router = Router();
    // دعم طلبات HEAD (للتحقق من الحجم) و GET (للتحميل)
    router.head('/video', _handleRequest);
    router.get('/video', _handleRequest);

    try {
      // ✅ 1. الربط بـ AnyIPv4 (0.0.0.0) لحل مشاكل رفض الاتصال في أندرويد
      // ✅ 2. shared: true يحسن الأداء عند تعدد الطلبات المتزامنة (صوت + فيديو)
      _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port, shared: true);
      
      _server?.autoCompress = false; // تعطيل الضغط لتسريع البث
      _server?.idleTimeout = null;   // منع السيرفر من إغلاق الاتصال عند الإيقاف المؤقت
      
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
        FirebaseCrashlytics.instance.log("❌ File not found: $decodedPath");
        return Response.notFound('File not found');
      }

      // ✅ استخدام octet-stream هو الخيار الأكثر أماناً للملفات المشفرة
      // يجبر المشغل على فحص الترويسة الحقيقية بعد فك التشفير
      String contentType = 'application/octet-stream'; 
      if (decodedPath.toLowerCase().contains('.pdf')) contentType = 'application/pdf';

      final encryptedLength = await file.length();
      
      // ✅ استدعاء ثوابت التشفير لضمان التوافق التام مع طريقة الكتابة
      final int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;
      final int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      final int overhead = encChunkSize - plainChunkSize; 

      // حساب الحجم الأصلي (مفكوك التشفير) بناءً على عدد الكتل
      final int totalChunks = (encryptedLength / encChunkSize).ceil();
      if (totalChunks == 0) return Response.ok('');

      final int originalFileSize = ((totalChunks - 1) * plainChunkSize) + max(0, (encryptedLength - ((totalChunks - 1) * encChunkSize)) - overhead);

      // معالجة طلب النطاق (Range Request)
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

      // الرد على طلب HEAD بالبيانات الوصفية فقط
      if (request.method == 'HEAD') {
        return Response.ok(null, headers: {
            'Content-Type': contentType,
            'Content-Length': originalFileSize.toString(),
            'Accept-Ranges': 'bytes',
        });
      }

      // ✅ بدء البث مع هيدرز محسنة
      return Response(
        206, 
        body: _createDecryptedStream(file, start, end),
        headers: {
          'Content-Type': contentType, 
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$originalFileSize',
          'Accept-Ranges': 'bytes',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache', // منع التخزين المؤقت المزدوج
          'Connection': 'keep-alive',  // الحفاظ على الاتصال مفتوحاً
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
      
      // ✅ استخدام نفس أحجام الكتل المستخدمة في التشفير
      const int plainChunkSize = EncryptionHelper.CHUNK_SIZE;
      const int encChunkSize = EncryptionHelper.ENCRYPTED_CHUNK_SIZE;

      // تحديد أي كتلة مشفرة تحتوي على البايت المطلوب
      int startChunkIndex = reqStart ~/ plainChunkSize;
      int endChunkIndex = reqEnd ~/ plainChunkSize;
      final fileLen = await file.length();

      for (int i = startChunkIndex; i <= endChunkIndex; i++) {
        // حساب موقع القراءة في الملف المشفر
        int seekPos = i * encChunkSize;
        if (seekPos >= fileLen) break;

        await raf.setPosition(seekPos);
        
        // قراءة كتلة كاملة (أو ما تبقى في نهاية الملف)
        int bytesToRead = min(encChunkSize, fileLen - seekPos);
        
        // حماية من القراءة الصفرية
        if (bytesToRead <= EncryptionHelper.IV_LENGTH) break;

        Uint8List encryptedBlock = await raf.read(bytesToRead);
        
        try {
          // ✅ عملية فك التشفير للكتلة الحالية
          Uint8List decryptedBlock = EncryptionHelper.decryptBlock(encryptedBlock);

          // حساب الجزء المطلوب من الكتلة المفكوكة (لأن الطلب قد يكون لجزء من المنتصف)
          int blockStartInPlain = i * plainChunkSize;
          int sliceStart = max(0, reqStart - blockStartInPlain);
          int sliceEnd = min(decryptedBlock.length, reqEnd - blockStartInPlain + 1);

          if (sliceStart < sliceEnd) {
            yield decryptedBlock.sublist(sliceStart, sliceEnd);
          }
        } catch (e) {
           print("⚠️ Decryption Skip at chunk $i: $e");
           // ✅ في حال فشل كتلة واحدة، نتجاوزها ونكمل للكتلة التالية
           // هذا يمنع توقف الفيديو بالكامل ويسمح بتجاوز الأجزاء التالفة
           continue; 
        }
      }
    } catch(e) {
       print("Stream Error: $e");
       // لا نرمي الخطأ لكي لا ينهار السيرفر، بل ننهي الستريم بهدوء
    } finally {
      await raf?.close();
    }
  }
}
