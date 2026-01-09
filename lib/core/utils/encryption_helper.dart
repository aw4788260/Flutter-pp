import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionHelper {
  // يجب أن يكون المفتاح 32 حرفاً
  static final key = encrypt.Key.fromUtf8('MySecretKeyForEduApp123456789012'); 
  static final iv = encrypt.IV.fromLength(16); 

  static final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
}
