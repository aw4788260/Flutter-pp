import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class FileCryptoService {
  static final _algorithm = Chacha20(macAlgorithm: MacAlgorithm.empty);
  static const int NONCE_LENGTH = 12;
  
  static SecretKey? _key;
  static final _storage = const FlutterSecureStorage();

  static Future<void> init() async {
    if (_key != null) return;

    String? storedKey = await _storage.read(key: 'docs_chacha_key');
    List<int> keyBytes;

    if (storedKey == null) {
      keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
      await _storage.write(key: 'docs_chacha_key', value: base64Encode(keyBytes));
    } else {
      keyBytes = base64Decode(storedKey);
    }

    _key = SecretKey(keyBytes);
  }

  static Future<void> encryptFile(String inputPath, String outputPath) async {
    await init();

    final inFile = File(inputPath);
    final outFile = File(outputPath);
    final ios = outFile.openWrite();
    
    final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
    ios.add(nonce);

    final stream = _algorithm.encryptStream(
      inFile.openRead(),
      secretKey: _key!,
      nonce: nonce,
      onMac: (mac) {}, // ✅ مطلوب إجبارياً في الإصدارات الحديثة
    );

    await ios.addStream(stream);
    await ios.close();
  }

  static Future<File> decryptToTempFile(String encryptedPath) async {
    await init();

    final encFile = File(encryptedPath);
    if (!await encFile.exists()) throw Exception("File missing");

    final raf = await encFile.open(mode: FileMode.read);
    
    try {
      final nonce = await raf.read(NONCE_LENGTH);
      
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/view_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final tempFile = File(tempPath);
      final sink = tempFile.openWrite();

      final totalLen = await encFile.length();
      final dataLen = totalLen - NONCE_LENGTH;

      await raf.setPosition(NONCE_LENGTH);

      Stream<List<int>> fileStream() async* {
        const int bufferSize = 512 * 1024; 
        int left = dataLen;
        while (left > 0) {
          int toRead = left < bufferSize ? left : bufferSize;
          yield await raf.read(toRead);
          left -= toRead;
        }
      }

      final decryptStream = _algorithm.decryptStream(
        fileStream(),
        secretKey: _key!,
        nonce: nonce,
        mac: Mac.empty, // ✅ مطلوب إجبارياً (Mac.empty لأننا عطلنا الـ MAC)
      );

      await sink.addStream(decryptStream);
      await sink.close();
      
      return tempFile;

    } finally {
      await raf.close();
    }
  }
}
