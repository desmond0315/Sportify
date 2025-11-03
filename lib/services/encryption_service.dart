import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

class EncryptionService {
  // Generate a key from chat ID (consistent with web)
  static encrypt.Key _generateKeyFromChatId(String chatId) {
    // Use SHA-256 to create a 32-byte key from chatId
    final bytes = utf8.encode(chatId);
    final hash = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(hash.bytes));
  }

  // Generate IV (Initialization Vector) from timestamp
  static encrypt.IV _generateIV() {
    // Use timestamp to generate a unique IV for each message
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    // Pad to exactly 16 characters
    final paddedTimestamp = timestamp.padRight(16, '0').substring(0, 16);
    final bytes = utf8.encode(paddedTimestamp);
    return encrypt.IV(Uint8List.fromList(bytes));
  }

  /// Encrypt a message
  static Map<String, String> encryptMessage(String plainText, String chatId) {
    try {
      final key = _generateKeyFromChatId(chatId);
      final iv = _generateIV();

      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      print('Encrypting message:');
      print('   Plain text: $plainText');
      print('   Chat ID: $chatId');
      print('   IV: ${iv.base64}');
      print('   Encrypted: ${encrypted.base64}');

      return {
        'encrypted': encrypted.base64,
        'iv': iv.base64,
      };
    } catch (e) {
      print('Encryption error: $e');
      // Return plaintext if encryption fails (fallback)
      return {
        'encrypted': plainText,
        'iv': '',
      };
    }
  }

  /// Decrypt a message
  static String decryptMessage(String encryptedText, String ivString, String chatId) {
    try {
      // If no IV, message is not encrypted (system message or fallback)
      if (ivString.isEmpty || encryptedText.isEmpty) {
        return encryptedText;
      }

      final key = _generateKeyFromChatId(chatId);
      final iv = encrypt.IV.fromBase64(ivString);

      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      final encrypted = encrypt.Encrypted.fromBase64(encryptedText);

      final decrypted = encrypter.decrypt(encrypted, iv: iv);

      print('Decrypting message:');
      print('   Chat ID: $chatId');
      print('   Encrypted: $encryptedText');
      print('   IV: $ivString');
      print('   Decrypted: $decrypted');

      return decrypted;
    } catch (e) {
      print('Decryption error: $e');
      print('   Encrypted text: $encryptedText');
      print('   IV: $ivString');
      print('   Chat ID: $chatId');
      return '[Encrypted message - unable to decrypt]';
    }
  }

  /// Encrypt message metadata (optional - for extra security)
  static String encryptMetadata(Map<String, dynamic> metadata, String chatId) {
    try {
      final jsonString = jsonEncode(metadata);
      final result = encryptMessage(jsonString, chatId);
      return result['encrypted']!;
    } catch (e) {
      print('Metadata encryption error: $e');
      return jsonEncode(metadata);
    }
  }

  /// Decrypt message metadata
  static Map<String, dynamic>? decryptMetadata(String encryptedMetadata, String ivString, String chatId) {
    try {
      if (ivString.isEmpty) {
        return jsonDecode(encryptedMetadata);
      }

      final decrypted = decryptMessage(encryptedMetadata, ivString, chatId);
      return jsonDecode(decrypted);
    } catch (e) {
      print('Metadata decryption error: $e');
      return null;
    }
  }
}