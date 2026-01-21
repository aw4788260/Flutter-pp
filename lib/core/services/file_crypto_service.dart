import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class FileCryptoService {
  // استخدام خوارزمية ChaCha20 السريعة جداً للأجهزة الضعيفة
  static final _algorithm = Chacha20(macAlgorithm: MacAlgorithm.empty);
  static const int NONCE_LENGTH = 12;
  
  static SecretKey? _key;
  static final _storage = const FlutterSecureStorage();

  // 1. تهيئة المفتاح (منفصل تماماً عن مفتاح الفيديو)
  static Future<void> init() async {
    if (_key != null) return;

    String? storedKey = await _storage.read(key: 'pdf_chacha_key');
    List<int> keyBytes;

    if (storedKey == null) {
      // إنشاء مفتاح جديد إذا لم يوجد
      keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
      await _storage.write(key: 'pdf_chacha_key', value: base64Encode(keyBytes));
    } else {
      keyBytes = base64Decode(storedKey);
    }

    _key = SecretKey(keyBytes);
  }

  // 2. دالة التشفير (تستخدم بعد التحميل مباشرة)
  static Future<void> encryptFile(String inputPath, String outputPath) async {
    await init();

    final inFile = File(inputPath);
    final outFile = File(outputPath);
    
    // قراءة الملف بالكامل (PDF عادة حجمه معقول ويمكن قراءته في الذاكرة للأجهزة الحديثة، 
    // ولكن للأجهزة الضعيفة سنستخدم الستريم لضمان عدم امتلاء الرام)
    final ios = outFile.openWrite();
    
    // إنشاء Nonce عشوائي لكل ملف
    final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
    
    // كتابة الـ Nonce في بداية الملف المشفر
    ios.add(nonce);

    // التشفير المتدفق
    final stream = _algorithm.encryptStream(
      inFile.openRead(),
      secretKey: _key!,
      nonce: nonce,
    );

    await ios.addStream(stream);
    await ios.close();
  }

  // 3. دالة فك التشفير (تنتج ملفاً مؤقتاً جاهزاً للعرض)
  static Future<File> decryptToTempFile(String encryptedPath) async {
    await init();

    final encFile = File(encryptedPath);
    if (!await encFile.exists()) throw Exception("Encrypted file not found");

    final raf = await encFile.open(mode: FileMode.read);
    
    try {
      // قراءة الـ Nonce
      final nonce = await raf.read(NONCE_LENGTH);
      
      // تجهيز ملف مؤقت
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/temp_view_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final tempFile = File(tempPath);
      final sink = tempFile.openWrite();

      // حساب حجم البيانات المتبقية
      final totalLen = await encFile.length();
      final dataLen = totalLen - NONCE_LENGTH;

      // القراءة من بعد الـ Nonce
      await raf.setPosition(NONCE_LENGTH);

      // دالة مساعدة لتحويل القراءة إلى Stream
      Stream<List<int>> fileStream() async* {
        const int bufferSize = 256 * 1024; // 256KB Chunk
        int left = dataLen;
        while (left > 0) {
          int toRead = left < bufferSize ? left : bufferSize;
          yield await raf.read(toRead);
          left -= toRead;
        }
      }

      // فك التشفير
      final decryptStream = _algorithm.decryptStream(
        fileStream(),
        secretKey: _key!,
        nonce: nonce,
      );

      await sink.addStream(decryptStream);
      await sink.close();
      
      return tempFile;

    } finally {
      await raf.close();
    }
  }
}
