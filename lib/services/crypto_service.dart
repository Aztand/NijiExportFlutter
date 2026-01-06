import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';
import 'dart:convert';

class CryptoService {
  static const String privacyPrefix = "[以下是隐私区域密文，请不要做任何编辑，否则可能导致解密失败]";
  static const String privacySuffix = "[以上是隐私日记，请不要编辑密文]";

  /// 对齐 PHP DiaryEncryptor:
  /// - AES-128-CBC
  /// - key = userid(UTF-8) 使用 Null Byte (\0) 补齐到 16 字节
  /// - iv = key
  static String decryptPrivacyCiphertext({
    required String ciphertext,
    required String userId,
  }) {
    try {
      // --- 核心修正部分：对齐 PHP 的 str_pad($id, 16, "\0") ---
      final List<int> userBytes = utf8.encode(userId);
      final Uint8List keyBytes = Uint8List(16); // 默认初始化即为 0 (Null Byte)
      for (int i = 0; i < userBytes.length && i < 16; i++) {
        keyBytes[i] = userBytes[i];
      }

      final key = Key(keyBytes);
      final iv = IV(keyBytes);
      // --------------------------------------------------

      final encrypter = Encrypter(
        AES(key, mode: AESMode.cbc, padding: 'PKCS7'),
      );

      final normalized = ciphertext.trim();

      // 先尝试 hex（PHP: bin2hex -> hex2bin）
      if (_looksLikeHex(normalized)) {
        try {
          final bytes = Uint8List.fromList(_hexToBytes(normalized));
          return encrypter.decrypt(Encrypted(bytes), iv: iv);
        } catch (_) {
          // fallthrough
        }
      }

      // 再尝试 base64（PHP: base64_decode）
      try {
        return encrypter.decrypt64(normalized, iv: iv);
      } catch (_) {
        // fallthrough
      }

      return "【隐私区域解密失败】";
    } catch (e) {
      // ignore: avoid_print
      print("解密失败: $e");
      return "【隐私区域解密失败】";
    }
  }

  /// 替换正文中的隐私标签段
  /// 接口保持原样，内部调用修正后的解密函数
  static String replacePrivacyBlocks({
    required String content,
    required String userId,
    required RegExp privacyPattern,
  }) {
    return content.replaceAllMapped(privacyPattern, (m) {
      final cipher = (m.group(1) ?? '').trim();
      final plain = decryptPrivacyCiphertext(
        ciphertext: cipher,
        userId: userId,
      );
      if (plain.startsWith('【隐私区域解密失败】')) {
        // 保留原始密文
        return m.group(0) ?? ("$privacyPrefix$cipher$privacySuffix");
      }
      return "[隐私区域开始]$plain[隐私区域结束]";
    });
  }

  /// 对齐 aardio 的 secureJson
  static String sanitizeJsonString(String raw) {
    return raw
        .replaceAll(r'\ud83c"', '"')
        .replaceAll(r'\ud83d"', '"')
        .replaceAll(r'\ud83e"', '"');
  }

  static bool _looksLikeHex(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), '');
    return t.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(t);
  }

  static List<int> _hexToBytes(String hex) {
    final t = hex.replaceAll(RegExp(r'\s+'), '');
    final out = <int>[];
    for (int i = 0; i < t.length; i += 2) {
      out.add(int.parse(t.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
