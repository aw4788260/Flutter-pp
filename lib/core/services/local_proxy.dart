import 'dart:io';
import 'dart:async';
import 'dart:isolate'; // ✅ مكتبة العزل
import 'dart:math';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:encrypt/encrypt.dart' as encrypt; // ✅ استيراد التشفير مباشرة لإعادة استخدامه في الخلفية
import '../utils/encryption_helper.dart';

class LocalProxyService {
  static final LocalProxyService _instance = LocalProxyService._internal();
  
  factory LocalProxyService() {
    return _instance;
  }
  
  LocalProxyService._internal();

  Isolate? _serverIsolate;
  final int port = 8080;
  
  // منفذ لاستقبال الرسائل من السيرفر الخلفي
  ReceivePort? _receivePort;
  
  // لضمان عدم تكرار التشغيل أو الطلب قبل الجاهزية
  Completer<void>? _readyCompleter;

  Future<void> start() async {
    // إذا كان السيرفر يعمل، تأكد أنه جاهز ثم عد
    if (_serverIsolate != null) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        await _readyCompleter!.future;
      }
      return;
    }

    _readyCompleter = Completer<void>();

    try {
      // 1. (Main Thread) نجهز التشفير ونجلب المفتاح هنا لأن التخزين لا يعمل في الخلفية
      await EncryptionHelper.init();
      // نحول المفتاح لنص لنقله للخيط الآخر
      String keyBase64 = EncryptionHelper.key.base64;
      
      _receivePort = ReceivePort();

      // 2. نشغل السيرفر في خيط منفصل (Isolate) ونمرر له المفتاح ومنفذ الرد
      _serverIsolate = await Isolate.spawn(
        _proxyServerEntryPoint, 
        _ProxyInitData(_receivePort!.sendPort, keyBase64, port)
      );
      
      // 3. ننتظر إشارة "READY" من السيرفر قبل السماح للتطبيق بالمتابعة
      // هذا يمنع خطأ "Connection Refused"
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

// -----------------------------------------------------------------------------
// ⚠️ منطقة الكود المعزول (Background Isolate Code)
// هذا الكود يعمل في ذاكرة منفصلة ولا يؤثر على واجهة التطبيق
// -----------------------------------------------------------------------------

// كلاس لنقل البيانات الضرورية لبدء السيرفر
class _ProxyInitData {
  final SendPort sendPort;
  final String keyBase64;
  final int port;

  _ProxyInitData(this.sendPort, this.keyBase64, this.port);
}

// نقطة البداية للخيط الجديد
void _proxyServerEntryPoint(_ProxyInitData initData) async {
   try {
     // 1. إعادة بناء محرك التشفير داخل الخيط الجديد باستخدام المفتاح المستلم
     final key = encrypt.Key.fromBase64(initData.keyBase64);
     final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
     
     // 2. إعداد المسارات
     final router = Router();
     // نمرر encrypter للدوال لأننا لا نستطيع استخدام EncryptionHelper.decryptBlock هنا
     router.get('/video', (Request req) => _handleRequest(req, encrypter));
     router.head('/video', (Request req) => _handleRequest(req, encrypter));
     
     // 3. تشغيل السيرفر
     // استخدام anyIPv4 ضروري جداً للأجهزة القديمة والمحاكيات
     final server = await shelf_io.serve(
       router, 
       InternetAddress.anyIPv4, 
       initData.port, 
       shared: false
     );
     
     server.autoCompress = false;
     // مهلة طويلة (60 ثانية) لمنع قطع الاتصال إذا تأخر المعالج
     server.idleTimeout = const Duration(seconds: 60);
     
     // 4. إبلاغ الخيط الرئيسي أننا جاهزون للاستقبال
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
    
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    String contentType = 'video/mp4'; 
    if (decodedPath.toLowerCase().contains('.pdf')) contentType = 'application/pdf';

    final encryptedLength = await file.length();
    
    // تعريف الثوابت محلياً داخل العزل لضمان الوصول إليها
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
        'Connection': 'keep-alive', // إبقاء الاتصال حياً مهم جداً
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
    
    // ثوابت محلية
    const int CHUNK_SIZE = 128 * 1024;
    const int IV_LENGTH = 12;
    const int TAG_LENGTH = 16;
    const int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

    int startChunkIndex = reqStart ~/ CHUNK_SIZE;
    int endChunkIndex = reqEnd ~/ CHUNK_SIZE;
    final fileLen = await file.length();

    for (int i = startChunkIndex; i <= endChunkIndex; i++) {
      if (totalSent >= requiredLength) break;

      int seekPos = i * ENCRYPTED_CHUNK_SIZE;
      if (seekPos >= fileLen) break;

      await raf.setPosition(seekPos);
      
      int bytesToRead = min(ENCRYPTED_CHUNK_SIZE, fileLen - seekPos);
      if (bytesToRead <= IV_LENGTH) break;

      Uint8List encryptedBlock = await raf.read(bytesToRead);
      Uint8List outputBlock;

      try {
        // فك التشفير يدوياً باستخدام Encrypter المحلي
        if (encryptedBlock.length < IV_LENGTH) {
             throw Exception("Invalid block size");
        }
        final iv = encrypt.IV(encryptedBlock.sublist(0, IV_LENGTH));
        final cipherBytes = encryptedBlock.sublist(IV_LENGTH);
        
        final decrypted = encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: iv);
        outputBlock = Uint8List.fromList(decrypted);

      } catch (e) {
         print("Decryption Error at chunk $i: $e");
         // إرسال بيانات فارغة لتجنب قطع البث في حال وجود خطأ بكتلة واحدة
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
    // تعويض الفجوات الصغيرة جداً إن وجدت لإرضاء المشغل
    if (totalSent < requiredLength) {
        int missingBytes = requiredLength - totalSent;
        if (missingBytes < 512 * 1024) {
           yield Uint8List(missingBytes);
        }
    }
    await raf?.close();
  }
}
