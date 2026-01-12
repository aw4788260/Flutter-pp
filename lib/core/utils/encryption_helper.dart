import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// ✅ إضافة استيراد Crashlytics
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class EncryptionHelper {
  // حجم كتلة البيانات الصافية (بدون تشفير) - 64KB
  static const int CHUNK_SIZE = 64 * 1024;
  
  // طول الـ IV (12 bytes for GCM)
  static const int IV_LENGTH = 12;
  
  // طول الـ Tag (16 bytes for GCM/MAC)
  static const int TAG_LENGTH = 16;
  
  // الحجم الكلي للكتلة المشفرة على القرص
  static const int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

  static encrypt.Key? _key;
  static final _storage = const FlutterSecureStorage();

  /// تهيئة المفتاح
  static Future<void> init() async {
    try {
      // محاولة قراءة المفتاح من التخزين الآمن
      String? storedKey = await _storage.read(key: 'app_master_key');
      
      if (storedKey == null) {
        FirebaseCrashlytics.instance.log("EncryptionHelper: Generating new master key");
        
        // توليد مفتاح عشوائي جديد 32 بايت (AES-256)
        final keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
        storedKey = base64UrlEncode(keyBytes);
        
        // حفظ المفتاح بأمان
        await _storage.write(key: 'app_master_key', value: storedKey);
      } else {
        FirebaseCrashlytics.instance.log("EncryptionHelper: Master key loaded from storage");
      }
      
      // تحميل المفتاح في الذاكرة
      _key = encrypt.Key.fromBase64(storedKey);

    } catch (e, stack) {
      // ✅ تسجيل فشل التهيئة (خطأ حرج)
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'CRITICAL: EncryptionHelper.init failed',
        fatal: true // نعتبره خطأ قاتل لأنه سيمنع تشغيل أي فيديو
      );
      throw Exception("Failed to initialize encryption: $e");
    }
  }

  /// getter للوصول للمفتاح
  static encrypt.Key get key {
    if (_key == null) {
      final e = Exception("Encryption Key not initialized! Call EncryptionHelper.init() first.");
      FirebaseCrashlytics.instance.recordError(e, null, reason: 'Key access before init');
      throw e;
    }
    return _key!;
  }

  /// تشفير كتلة من البيانات باستخدام AES-GCM
  static Uint8List encryptBlock(Uint8List data) {
    if (_key == null) throw Exception("Key not initialized!");

    try {
      // توليد IV عشوائي
      final iv = encrypt.IV.fromSecureRandom(IV_LENGTH);
      
      final encrypter = encrypt.Encrypter(encrypt.AES(_key!, mode: encrypt.AESMode.gcm));
      
      final encrypted = encrypter.encryptBytes(data, iv: iv);

      final result = BytesBuilder();
      result.add(iv.bytes);
      result.add(encrypted.bytes);
      
      return result.toBytes();

    } catch (e, stack) {
      // ✅ تسجيل خطأ أثناء التشفير
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'EncryptBlock Failed',
        information: ['Data Length: ${data.length}']
      );
      throw e;
    }
  }

  /// فك تشفير كتلة من البيانات المشفرة
  static Uint8List decryptBlock(Uint8List encryptedBlock) {
    if (_key == null) throw Exception("Key not initialized!");

    try {
      // 1. التحقق من الطول
      if (encryptedBlock.length < IV_LENGTH) {
          throw Exception("Invalid encrypted block size: ${encryptedBlock.length}");
      }

      // 2. استخراج الـ IV
      final ivBytes = encryptedBlock.sublist(0, IV_LENGTH);
      final iv = encrypt.IV(ivBytes);

      // 3. استخراج البيانات المشفرة
      final cipherBytes = encryptedBlock.sublist(IV_LENGTH);

      // 4. فك التشفير
      final encrypter = encrypt.Encrypter(encrypt.AES(_key!, mode: encrypt.AESMode.gcm));
      
      final decrypted = encrypter.decryptBytes(
        encrypt.Encrypted(cipherBytes), 
        iv: iv
      );

      return Uint8List.fromList(decrypted);

    } catch (e, stack) {
      // ✅ تسجيل خطأ تفصيلي أثناء فك التشفير
      // هذا الخطأ هو الأكثر شيوعاً (Mac check failed) إذا كان المفتاح خطأ أو الملف تالف
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'DecryptBlock Failed',
        information: [
          'Block Size: ${encryptedBlock.length}',
          'IV Length: $IV_LENGTH',
          'Expected Tag Length: $TAG_LENGTH'
        ]
      );
      throw e;
    }
  }

  /// دالة مساعدة لفك تشفير ملف كامل
  static Future<File> decryptFileFull(File encryptedFile, String outputPath) async {
    if (_key == null) await init();

    if (!await encryptedFile.exists()) {
      final e = Exception("Source file does not exist: ${encryptedFile.path}");
      FirebaseCrashlytics.instance.recordError(e, null);
      throw e;
    }

    final rafRead = await encryptedFile.open(mode: FileMode.read);
    final rafWrite = await File(outputPath).open(mode: FileMode.write);

    try {
      final int fileLength = await encryptedFile.length();
      int currentPos = 0;
      const int blockSize = ENCRYPTED_CHUNK_SIZE;

      FirebaseCrashlytics.instance.log("Starting full decryption: ${encryptedFile.path} ($fileLength bytes)");

      while (currentPos < fileLength) {
        int bytesToRead = blockSize;
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }

        Uint8List chunk = await rafRead.read(bytesToRead);
        if (chunk.isEmpty) break;

        // محاولة فك تشفير الكتلة
        try {
          Uint8List decryptedChunk = decryptBlock(chunk);
          await rafWrite.writeFrom(decryptedChunk);
        } catch (blockError) {
          // تسجيل الخطأ المحدد للكتلة
          FirebaseCrashlytics.instance.log("Failed at position: $currentPos");
          throw blockError; // إعادة رمي الخطأ ليتم التقاطه في الـ finally أو الخارج
        }

        currentPos += chunk.length;
      }
      
      FirebaseCrashlytics.instance.log("Full decryption completed successfully");

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'DecryptFileFull Failed',
        information: ['File: ${encryptedFile.path}']
      );
      throw e;
    } finally {
      await rafRead.close();
      await rafWrite.flush();
      await rafWrite.close();
    }
    
    return File(outputPath);
  }
}
