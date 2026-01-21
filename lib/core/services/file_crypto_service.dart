import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class FileCryptoService {
  // ✅ استخدام ChaCha20 (بدون MAC) لأقصى سرعة ممكنة على المعالجات القديمة
  static final _algorithm = Chacha20(macAlgorithm: MacAlgorithm.empty);
  static const int NONCE_LENGTH = 12;
  
  static SecretKey? _key;
  static final _storage = const FlutterSecureStorage();

  /// 1. تهيئة مفتاح خاص للمستندات (منفصل عن الفيديو)
  static Future<void> init() async {
    if (_key != null) return;

    // محاولة قراءة المفتاح المخزن
    String? storedKey = await _storage.read(key: 'docs_chacha_key');
    List<int> keyBytes;

    if (storedKey == null) {
      // توليد مفتاح عشوائي جديد 32 بايت
      keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
      await _storage.write(key: 'docs_chacha_key', value: base64Encode(keyBytes));
    } else {
      keyBytes = base64Decode(storedKey);
    }

    _key = SecretKey(keyBytes);
  }

  /// 2. تشفير الملف (يستخدم مرة واحدة بعد التحميل)
  static Future<void> encryptFile(String inputPath, String outputPath) async {
    await init();

    final inFile = File(inputPath);
    final outFile = File(outputPath);
    
    // استخدام Stream لتفادي استهلاك الرام للملفات الكبيرة
    final ios = outFile.openWrite();
    
    // إنشاء Nonce عشوائي لكل ملف (لزيادة الأمان)
    final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
    
    // حفظ الـ Nonce في مقدمة الملف المشفر
    ios.add(nonce);

    // بدء التشفير المتدفق
    final stream = _algorithm.encryptStream(
      inFile.openRead(),
      secretKey: _key!,
      nonce: nonce,
      onMac: (mac) {}, // ✅ تصحيح: إضافة معامل onMac الإجباري
    );

    await ios.addStream(stream);
    await ios.close();
  }

  /// 3. فك التشفير لملف مؤقت (للعرض السلس)
  static Future<File> decryptToTempFile(String encryptedPath) async {
    await init();

    final encFile = File(encryptedPath);
    if (!await encFile.exists()) throw Exception("File missing");

    // فتح الملف للقراءة العشوائية
    final raf = await encFile.open(mode: FileMode.read);
    
    try {
      // قراءة الـ Nonce من المقدمة
      final nonce = await raf.read(NONCE_LENGTH);
      
      // تجهيز المسار المؤقت
      final tempDir = await getTemporaryDirectory();
      // اسم عشوائي لضمان عدم التضارب
      final tempPath = '${tempDir.path}/view_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final tempFile = File(tempPath);
      final sink = tempFile.openWrite();

      final totalLen = await encFile.length();
      final dataLen = totalLen - NONCE_LENGTH;

      // القراءة من بعد الـ Nonce
      await raf.setPosition(NONCE_LENGTH);

      // دالة مساعدة لتحويل القراءة إلى Stream كتل كبيرة (512KB) للسرعة
      Stream<List<int>> fileStream() async* {
        const int bufferSize = 512 * 1024; 
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
        mac: Mac.empty, // ✅ تصحيح: إضافة معامل mac الإجباري
      );

      await sink.addStream(decryptStream);
      await sink.close();
      
      return tempFile;

    } finally {
      await raf.close();
    }
  }
}
