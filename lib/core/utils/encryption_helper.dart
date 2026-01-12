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

  /// ✅ دالة فك التشفير المتوافقة مع النظام الحديث (Stream-Based)
  /// تستخدم هذه الدالة لفك تشفير الملفات التي تحتاج لفتحها بتطبيقات خارجية (مثل PDF)
  /// ولا تسبب استهلاك عالي للذاكرة (RAM Safe).
  static Future<File> decryptFile(File encryptedFile, String outputPath) async {
    if (!await encryptedFile.exists()) {
      throw Exception("Source file does not exist");
    }

    // فتح قنوات للقراءة والكتابة
    final rafRead = await encryptedFile.open(mode: FileMode.read);
    final rafWrite = await File(outputPath).open(mode: FileMode.write);

    try {
      // إعدادات فك التشفير (بدون Padding لأننا سنتعامل معه يدوياً)
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc, padding: null));

      // الـ IV المبدئي
      List<int> currentIV = _iv.bytes;
      
      const int bufferSize = 4096 * 16; // قراءة 64KB في كل دفعة
      final int fileLength = await encryptedFile.length();
      int currentPos = 0;

      while (currentPos < fileLength) {
        // قراءة قطعة من الملف المشفر
        Uint8List chunk = await rafRead.read(bufferSize);
        if (chunk.isEmpty) break;

        // ✅ حفظ آخر 16 بايت من القطعة المشفرة الحالية لتكون هي الـ IV للقطعة التالية
        // (هذه قاعدة AES-CBC)
        List<int> nextIV = chunk.sublist(chunk.length - 16);

        // فك تشفير القطعة باستخدام الـ IV الحالي
        final decryptedChunk = encrypter.decryptBytes(
          encrypt.Encrypted(chunk), 
          iv: encrypt.IV(Uint8List.fromList(currentIV))
        );

        // تحديث الـ IV للدورة القادمة
        currentIV = nextIV;

        // ✅ معالجة الحشو (PKCS7 Padding) للقطعة الأخيرة فقط
        if (currentPos + chunk.length >= fileLength) {
           int padLength = decryptedChunk.last;
           
           // التحقق من صحة الحشو (يجب أن يكون بين 1 و 16)
           if (padLength > 0 && padLength <= 16) {
             final validLength = decryptedChunk.length - padLength;
             await rafWrite.writeFrom(decryptedChunk.sublist(0, validLength));
           } else {
             // في حال كان الملف غير محشو بشكل قياسي (نادر)، نكتبه كما هو
             await rafWrite.writeFrom(decryptedChunk);
           }
        } else {
           // كتابة البيانات المفكوكة (ليست الأخيرة)
           await rafWrite.writeFrom(decryptedChunk);
        }

        currentPos += chunk.length;
      }

    } finally {
      // إغلاق الملفات لتحرير الموارد
      await rafRead.close();
      await rafWrite.flush();
      await rafWrite.close();
    }
    
    return File(outputPath);
  }
}
