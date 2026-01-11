import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionHelper {
  // مفاتيح التشفير (تأكد أنها تطابق ما تستخدمه في الباك اند)
  static final _key = encrypt.Key.fromUtf8('12345678901234567890123456789012'); // 32 chars
  static final _iv = encrypt.IV.fromUtf8('1234567890123456'); // 16 chars

  // الكائنات المساعدة (Getters)
  static encrypt.Key get key => _key;
  static encrypt.IV get iv => _iv;
  static encrypt.Encrypter get encrypter => 
      encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));

  /// ✅ الدالة المفقودة التي يطلبها المشغل لفك تشفير الملفات
  static Future<File> decryptFile(File encryptedFile, String outputPath) async {
    if (!await encryptedFile.exists()) {
      throw Exception("Source file does not exist");
    }

    // قراءة البيانات المشفرة
    final videoData = await encryptedFile.readAsBytes();
    
    // فك التشفير
    final decryptedData = encrypter.decryptBytes(
      encrypt.Encrypted(videoData), 
      iv: _iv
    );
    
    // كتابة الملف المفكوك
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(decryptedData, flush: true);
    
    return outputFile;
  }
}
