import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class EncryptionHelper {
  // Default fallback size (can be overridden dynamically)
  static const int DEFAULT_CHUNK_SIZE = 64 * 1024; 
  
  static const int IV_LENGTH = 12;
  static const int TAG_LENGTH = 16;
  
  // Helper to calculate encrypted size for any given plain chunk size
  static int getEncryptedSize(int plainChunkSize) {
    return IV_LENGTH + plainChunkSize + TAG_LENGTH;
  }

  // Backwards compatibility for old code referencing this
  static const int CHUNK_SIZE = DEFAULT_CHUNK_SIZE; 
  static const int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

  static encrypt.Key? _key;
  
  // Keep the encrypter instance alive for performance (10x speedup)
  static encrypt.Encrypter? _encrypter;
  
  static final _storage = const FlutterSecureStorage();

  /// Initialize Key and Encrypter
  static Future<void> init() async {
    try {
      String? storedKey = await _storage.read(key: 'app_master_key');
      
      if (storedKey == null) {
        FirebaseCrashlytics.instance.log("EncryptionHelper: Generating new master key");
        final keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
        storedKey = base64UrlEncode(keyBytes);
        await _storage.write(key: 'app_master_key', value: storedKey);
      } else {
        FirebaseCrashlytics.instance.log("EncryptionHelper: Master key loaded from storage");
      }
      
      _key = encrypt.Key.fromBase64(storedKey);

      // ✅ Create Encrypter instance once
      _encrypter = encrypt.Encrypter(encrypt.AES(_key!, mode: encrypt.AESMode.gcm));

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'CRITICAL: EncryptionHelper.init failed',
        fatal: true 
      );
      throw Exception("Failed to initialize encryption: $e");
    }
  }

  static encrypt.Key get key {
    if (_key == null) {
      final e = Exception("Encryption Key not initialized! Call EncryptionHelper.init() first.");
      FirebaseCrashlytics.instance.recordError(e, null, reason: 'Key access before init');
      throw e;
    }
    return _key!;
  }

  /// Encrypt a single block of data
  static Uint8List encryptBlock(Uint8List data) {
    if (_encrypter == null) throw Exception("Encryption not initialized! Call init() first.");

    try {
      final iv = encrypt.IV.fromSecureRandom(IV_LENGTH);
      
      // ✅ Use pre-initialized encrypter
      final encrypted = _encrypter!.encryptBytes(data, iv: iv);

      final result = BytesBuilder();
      result.add(iv.bytes);
      result.add(encrypted.bytes);
      
      return result.toBytes();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'EncryptBlock Failed',
        information: ['Data Length: ${data.length}']
      );
      throw e;
    }
  }

  /// Decrypt a single block
  static Uint8List decryptBlock(Uint8List encryptedBlock) {
    if (_encrypter == null) throw Exception("Encryption not initialized! Call init() first.");

    try {
      if (encryptedBlock.length < IV_LENGTH) {
          throw Exception("Invalid encrypted block size: ${encryptedBlock.length}");
      }

      final iv = encrypt.IV(encryptedBlock.sublist(0, IV_LENGTH));
      final cipherBytes = encryptedBlock.sublist(IV_LENGTH);

      // ✅ Fast decryption using cached instance
      final decrypted = _encrypter!.decryptBytes(
        encrypt.Encrypted(cipherBytes), 
        iv: iv
      );

      return Uint8List.fromList(decrypted);

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'DecryptBlock Failed',
        information: [
          'Block Size: ${encryptedBlock.length}',
          'IV Length: $IV_LENGTH'
        ]
      );
      throw e;
    }
  }

  /// Helper to fully decrypt a file (e.g. for PDF viewing)
  /// Now accepts [chunkSize] to handle different device settings
  static Future<File> decryptFileFull(File encryptedFile, String outputPath, {int chunkSize = DEFAULT_CHUNK_SIZE}) async {
    if (_key == null) await init();

    if (!await encryptedFile.exists()) {
      throw Exception("Source file does not exist: ${encryptedFile.path}");
    }

    final rafRead = await encryptedFile.open(mode: FileMode.read);
    final rafWrite = await File(outputPath).open(mode: FileMode.write);

    try {
      final int fileLength = await encryptedFile.length();
      int currentPos = 0;
      
      // Calculate block size dynamically based on the passed chunk size
      final int encryptedBlockSize = getEncryptedSize(chunkSize);

      FirebaseCrashlytics.instance.log("Starting full decryption: ${encryptedFile.path} with chunk: $chunkSize");

      while (currentPos < fileLength) {
        int bytesToRead = encryptedBlockSize;
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }

        Uint8List chunk = await rafRead.read(bytesToRead);
        if (chunk.isEmpty) break;

        try {
          Uint8List decryptedChunk = decryptBlock(chunk);
          await rafWrite.writeFrom(decryptedChunk);
        } catch (blockError) {
          FirebaseCrashlytics.instance.log("Failed at position: $currentPos");
          throw blockError;
        }

        currentPos += chunk.length;
      }
      
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'DecryptFileFull Failed');
      throw e;
    } finally {
      await rafRead.close();
      await rafWrite.flush();
      await rafWrite.close();
    }
    
    return File(outputPath);
  }
}
