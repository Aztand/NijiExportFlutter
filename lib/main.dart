import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart'; // 引入主页面
import 'core/theme.dart';
import 'platform/window_manager_initializer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows 端窗口初始化（其他平台为 no-op），避免 window_manager 干扰非 Windows 端构建/运行
  await initWindowManagerIfNeeded();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '你记日记导出',
      theme: appTheme, // 使用我们在 core 里定义的皮肤
      // 1. 定义初始路由
      initialRoute: '/',
      // 2. 定义路由表
      routes: {
        '/': (context) => const LoginScreen(),
        '/main': (context) => const MainScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
