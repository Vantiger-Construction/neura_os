import 'dart:convert';

/// Placeholder encryptor for memory content.
/// Uses base64 encoding as a stand-in until a real encryption backend is wired.
class MemoryEncryptor {
  String encrypt(String plainText) {
    return base64Encode(utf8.encode(plainText));
  }

  String decrypt(String encoded) {
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return encoded;
    }
  }
}
