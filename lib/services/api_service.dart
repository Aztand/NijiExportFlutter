import 'package:dio/dio.dart';
import '../core/constants.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 引入插件
import 'dart:convert';

class ApiService {
  ApiService() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('auth_token');
            if (token != null && token.isNotEmpty) {
              options.headers['auth'] = 'token $token';
            }
          } catch (_) {
            // ignore prefs errors
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: AppConstants.getBaseHeaders(),
    ),
  );

  // --- JSON 清洗：对齐 aardio 的 secureJson（删除常见 emoji 高代理对前缀，避免 JSON 解析失败）
  String _sanitizeJsonString(String raw) {
    return raw
        .replaceAll(r'\ud83c"', '"')
        .replaceAll(r'\ud83d"', '"')
        .replaceAll(r'\ud83e"', '"');
  }

  Map<String, dynamic> _decodePossiblyBrokenJson(String raw) {
    final fixed = _sanitizeJsonString(raw);
    final decoded = jsonDecode(fixed);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'_raw': decoded};
  }

  // 1. 保存 Token 和用户信息
  Future<void> saveAuthData(String token, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setInt('user_id', userId);
  }

  // 2. 获取存储的 Token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // 3. 登录方法（更新版）
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await _dio.post(
        '/api/login/',
        data: {'email': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        // 如果返回了 token 和 userid，直接在此处保存
        if (data['token'] != null && data['user_config'] != null) {
          await saveAuthData(data['token'], data['user_config']['userid']);
        }
        return data;
      }
    } on DioException catch (e) {
      return {'error': true, 'message': e.message};
    }
    return null;
  }

  // 获取格言和用户信息（sync 返回 user_config / diaries / images 等）
  Future<Map<String, dynamic>?> sync() async {
    try {
      // 注意：aardio 用 POST；且可能存在非法 unicode，改成 plain 手动解析
      final response = await _dio.post(
        '/api/v2/sync/',
        data: {},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
      if (response.statusCode == 200) {
        return _decodePossiblyBrokenJson(response.data as String);
      }
    } catch (e) {
      // ignore: avoid_print
      print("获取初始数据失败: $e");
    }
    return null;
  }

  Future<Map<String, dynamic>?> allByIds({
    required String userId,
    required int diaryId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/diary/all_by_ids/$userId/',
        data: {'diary_ids': diaryId},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
      if (response.statusCode == 200) {
        return _decodePossiblyBrokenJson(response.data as String);
      }
    } catch (e) {
      // ignore: avoid_print
      print("拉取日记详情失败: $e");
    }
    return null;
  }

  Future<void> updateReadMark(int diaryId) async {
    try {
      await _dio.get('/api/update_read_mark/$diaryId/');
    } catch (_) {
      // 标记失败不影响导出
    }
  }

  /// 下载图片二进制（对应 aardio: https://f.nideriji.cn/api/image/{userid}/{imageId}/ ）
  ///
  /// - 成功返回 bytes
  /// - 图片不存在/已删除返回 null
  ///
  /// 注意：此接口在原实现中额外设置了 Host=f.nideriji.cn；这里保留以提高兼容性。
  Future<List<int>?> downloadImageBytes({
    required String userId,
    required int imageId,
  }) async {
    try {
      final url = '${AppConstants.imageBaseUrl}/api/image/$userId/$imageId/';
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Host': 'f.nideriji.cn'},
        ),
      );
      if (response.statusCode == 200 && response.data is List<int>) {
        final bytes = response.data as List<int>;
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (e) {
      // ignore: avoid_print
      print('下载图片失败 imageId=$imageId: $e');
    }
    return null;
  }
}
