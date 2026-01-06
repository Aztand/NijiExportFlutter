import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 仅在 Windows 端初始化 window_manager。
///
/// 这样可以避免：
/// - 在非 Windows 端调用 window_manager 导致的 MissingPluginException
/// - 非 Windows 端构建/部署被桌面窗口逻辑干扰
Future<void> initWindowManagerIfNeeded() async {
  if (!Platform.isWindows) return;

  // 必须加上这一行初始化插件
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(400, 700), // 设置细长的比例（类似手机）
    center: true, // 居中显示
    title: "你记日记导出",
    //backgroundColor: Colors.white,  //设置bgcolor后会看不清标题栏
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
