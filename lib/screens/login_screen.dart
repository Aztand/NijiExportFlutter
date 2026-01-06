import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 1.控制器：用于获取输入框的内容
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 2.状态变量：对应 aardio 的 remCheck 和 autoLoginCheck
  bool _isLoading = false;
  bool _rememberPassword = false;
  bool _autoLogin = false;
  bool _isObscure = true; // 控制密码可见性

  // 3. 引用我们的 ApiService
  final ApiService _apiService = ApiService();

  void _handleLogin() async {
    // 获取输入内容
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showErrorDialog("账号或密码不能为空");
      return;
    }

    // 开始加载
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _apiService.login(email, password);

      if (result != null && result['token'] != null) {
        // --- 新增：处理记住密码逻辑 ---
        final prefs = await SharedPreferences.getInstance();
        if (_rememberPassword) {
          await prefs.setString('saved_email', email);
          await prefs.setString('saved_password', password);
          await prefs.setBool('rem_password', true);
        } else {
          // 如果没勾选，清除掉旧的
          await prefs.remove('saved_email');
          await prefs.remove('saved_password');
          await prefs.setBool('rem_password', false);
        }

        // 保存自动登录状态
        await prefs.setBool('auto_login', _autoLogin);

        // 解析接口返回的用户数据 (假设结构与 aardio 版一致)
        final userConfig = result['user_config'];
        if (userConfig != null) {
          await prefs.setString('username', userConfig['name'] ?? "用户名");
          await prefs.setString(
            'description',
            userConfig['description'] ?? "这个人很懒，没有格言",
          );
          await prefs.setString('user_id', userConfig['userid'].toString());
          // 如果有头像字段，比如 head_url
          await prefs.setString(
            'avatar_url',
            userConfig['avatar'] != null
                ? "http://f.nideriji.cn${userConfig['avatar']}"
                : "",
          );
        }
        // 跳转到主页
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        _showErrorDialog("登录失败，请检查账号密码");
      }
    } catch (e) {
      _showErrorDialog("网络错误");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 辅助方法：显示错误弹窗
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("提示"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("好"),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberPassword = prefs.getBool('rem_password') ?? false;
      _autoLogin = prefs.getBool('auto_login') ?? false;

      if (_rememberPassword) {
        _emailController.text = prefs.getString('saved_email') ?? "";
        _passwordController.text = prefs.getString('saved_password') ?? "";
      }
    });

    // 如果开启了自动登录，直接触发登录函数
    if (_autoLogin && _emailController.text.isNotEmpty) {
      _handleLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 使用 SingleChildScrollView 防止手机键盘弹出时遮挡内容
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            children: [
              const SizedBox(height: 60),
              // 1. Logo 区域 (对应 loginForm.logoPic)
              Image.asset(
                'assets/logo.png',
                width: 150,
                height: 150,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              const Text(
                "你的日记",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.staticTextColor,
                ),
              ),
              const SizedBox(height: 40),

              // 2. 账号输入框 (对应 loginForm.emailEdit)
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  hintText: "账号",
                  fillColor: Colors.white,
                  filled: true,
                ),
              ),
              const SizedBox(height: 20),

              // 3. 密码输入框 (对应 loginForm.passwordEdit)
              TextField(
                controller: _passwordController,
                obscureText: _isObscure,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: "密码",
                  fillColor: Colors.white,
                  filled: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _isObscure = !_isObscure),
                  ),
                ),
              ),

              // 4. 勾选框区域 (对应 loginForm.remCheck 和 autoLoginCheck)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _rememberPassword,
                    onChanged: (val) {
                      setState(() {
                        _rememberPassword = val!;
                        // 如果取消记住密码，则自动取消自动登录
                        if (!_rememberPassword) _autoLogin = false;
                      });
                    },
                  ),
                  const Text("记住密码"),
                  const SizedBox(width: 20),
                  Checkbox(
                    value: _autoLogin,
                    onChanged: (val) {
                      setState(() {
                        _autoLogin = val!;
                        // 如果开启自动登录，必须勾选记住密码
                        if (_autoLogin) _rememberPassword = true;
                      });
                    },
                  ),
                  const Text("自动登录"),
                ],
              ),
              const SizedBox(height: 30),

              // 5. 登录按钮 (对应 loginForm.loginPlus)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin, // 加载中禁用按钮
                  child: _isLoading
                      ? const RepaintBoundary(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : const Text("登录", style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 12),
              // 6. 注册跳转 (对应 loginForm.regPlus)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, // 背景白色
                    foregroundColor: Colors.black, // 文字黑色
                    //side: const BorderSide(color: Colors.black), // 可选：加个黑边更显眼
                  ),

                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        content: const Text(
                          "就这么个第三方软件你还指望能注册？",
                          style: TextStyle(color: Colors.black), // 修改字体颜色
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("确认"),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text(
                    "注册",
                    style: TextStyle(fontSize: 18, color: Color(0xFF646464)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
