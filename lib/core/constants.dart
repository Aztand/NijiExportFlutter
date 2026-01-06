import 'package:flutter/material.dart';

class AppConstants {
  // --- API 地址 ---
  static const String baseUrl = "https://nideriji.cn";
  static const String loginUrl = "$baseUrl/api/login/";
  static const String syncUrl = "$baseUrl/api/v2/sync/";
  static const String diaryAllByIdsUrl = "$baseUrl/api/diary/all_by_ids/";
  static const String updateReadMarkUrl = "$baseUrl/api/update_read_mark/";
  static const String imageBaseUrl = "https://f.nideriji.cn";

  // --- UI 颜色 (将 aardio 的 14657884 转换为 Flutter 颜色) ---
  // Aardio 14657884 -> Hex: 0xDFAD5C (RGB顺序可能需根据视觉微调)
  // 这里我们按 Aardio 常见的 BGR/RGB 转换，假设为背景淡蓝色/紫色
  static const Color themeBgColor = Color(0xff5ca9df); // 0xDFAD5C 转换
  static const Color staticTextColor = Color(0xFFF0F0F0); // 15793151 转换

  // --- 默认请求头 ---
  static Map<String, String> getBaseHeaders() {
    return {
      "user-agent": "OhApp/3.7 Platform/Android",
      "Content-Type": "application/x-www-form-urlencoded",
    };
  }

  // --- 正则表达式 (对应你 Aardio 里的加密标签匹配) ---
  static final RegExp privacyPattern = RegExp(
    r"\[以下是隐私区域密文，请不要做任何编辑，否则可能导致解密失败\]([\s\S]+?)\s*\[以上是隐私日记，请不要编辑密文\]",
    multiLine: true,
  );
}
