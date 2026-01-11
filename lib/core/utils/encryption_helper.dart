import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionHelper {
  // ✅ 1. تعريف المفتاح كنص ثابت (32 حرفاً لـ AES-256)
  static const String _keyString = 'MySecretKeyForEduApp123456789012';
  
  // ✅ 2. تعريف الـ IV كنص ثابت (16 حرفاً)
  // تحذير: استخدام fromLength(16) يولد رقماً عشوائياً عند كل تشغيل
  // مما يتسبب في تلف الملفات المحملة سابقاً بعد إعادة تشغيل التطبيق.
  static const String _ivString = 'FixedIVForApp123'; // يجب أن يكون 16 حرفاً

  // ✅ 3. جعلنا الكائنات عامة (Public) ليتمكن الـ Proxy من استخدامها في البث
  static final key = encrypt.Key.fromUtf8(_keyString);
  static final iv = encrypt.IV.fromUtf8(_ivString);

  // الكائن الرئيسي للتشفير وفك التشفير العادي
  static final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
}
