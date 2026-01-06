import 'package:flutter/material.dart';
import 'constants.dart';

final appTheme = ThemeData(
  fontFamily: "Microsoft YaHei",
  primarySwatch: Colors.blue,
  scaffoldBackgroundColor: AppConstants.themeBgColor,
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: AppConstants.staticTextColor),
  ),
  // 全局 Dialog 风格：对齐 login_screen 点击“注册”弹出的“小对话框”
  dialogTheme: const DialogThemeData(
    backgroundColor: Color(0xFFFFFFFF),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    titleTextStyle: TextStyle(
      color: Colors.black,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    contentTextStyle: TextStyle(color: Colors.black, fontSize: 14),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: const Color(0xFF077F76)),
  ),
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.black, // 将种子颜色设为黑色
    primary: Colors.black,
  ),
  // 统一输入框样式
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    // 需求：文本输入框取消黑边（去掉 OutlineBorder 及 focus 黑色描边）
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    hintStyle: const TextStyle(color: Colors.grey),
  ),
  // 需求：勾选框白底黑勾
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith<Color>((states) {
      return Colors.white;
    }),
    checkColor: WidgetStateProperty.resolveWith<Color>((states) {
      return Colors.black;
    }),
    // 未勾选时也要有明显边框（在浅色弹层/白底场景下仍可见）
    side: const BorderSide(color: Colors.black54, width: 1),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF559DCF), // 你喜欢的蓝色
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), // 这里控制圆角大小
      ),
      elevation: 2, // 阴影深度
    ),
  ),
);
