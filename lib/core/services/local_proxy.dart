import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/encryption_helper.dart';

class LocalProxyService {
  HttpServer? _server;
  final int port = 8080;

  Future<void> start() async {
    if (_server != null) return;

    final router = Router();
    
    // نقطة النهاية: http://localhost:8080/video?path=...
    router.get('/video', _handleVideoRequest);

    try {
      _server = await shelf_io.serve(router, InternetAddress.loopbackIPv4, port);
      print('🔒 Local Proxy running on port ${_server!.port}');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Starting Local Proxy');
    }
  }

  Future<Response> _handleVideoRequest(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null) return Response.notFound('Path not provided');

    final file = File(path);
    if (!await file.exists()) return Response.notFound('File not found');

    try {
      // قراءة الملف بالكامل (للتبسيط، مع الملفات الكبيرة يفضل Stream)
      final encryptedBytes = await file.readAsBytes();
      
      // فك التشفير
      final decryptedBytes = EncryptionHelper.encrypter.decryptBytes(
        encrypt.Encrypted(encryptedBytes), 
        iv: EncryptionHelper.iv
      );

      // إرجاع الفيديو كمجرى بيانات (Stream)
      return Response.ok(
        decryptedBytes,
        headers: {
          'Content-Type': 'video/mp4', // أو video/mp2t حسب الصيغة المجمعة
          'Content-Length': decryptedBytes.length.toString(),
          'Access-Control-Allow-Origin': '*',
        },
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Proxy Decryption Error');
      return Response.internalServerError(body: 'Error decrypting video');
    }
  }

  void stop() {
    _server?.close();
    _server = null;
  }
}
