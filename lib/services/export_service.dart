import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import 'api_service.dart';
import 'crypto_service.dart';

class ExportProgress {
  final int current;
  final int total;
  final String message;

  const ExportProgress({
    required this.current,
    required this.total,
    required this.message,
  });
}

class ExportResult {
  final String filePath;
  final int exportedCount;

  const ExportResult({required this.filePath, required this.exportedCount});
}

class ExportService {
  final ApiService _api;

  ExportService({ApiService? api}) : _api = api ?? ApiService();

  /// 并发执行 items 的 action（限制最大并发数）。
  ///
  /// - concurrency <= 1 时等同串行。
  /// - action 内部异常会向外抛出并终止整个导出流程。
  Future<void> _forEachConcurrent<T>(
    List<T> items, {
    required int concurrency,
    required Future<void> Function(int index, T item) action,
  }) async {
    if (items.isEmpty) return;
    final c = concurrency < 1 ? 1 : concurrency;
    int nextIndex = 0;

    Future<void> runner() async {
      while (true) {
        final i = nextIndex++;
        if (i >= items.length) return;
        await action(i, items[i]);
      }
    }

    final startCount = c > items.length ? items.length : c;
    final futures = <Future<void>>[];
    for (int i = 0; i < startCount; i++) {
      futures.add(runner());
    }
    await Future.wait(futures);
  }

  /// 供 UI 在“点击按钮后立刻”触发权限申请使用。
  ///
  /// 需求：避免用户等待网络很久后才弹权限，误拒绝导致白等。
  Future<void> ensureExportPermissionIfNeeded() async {
    if (!Platform.isAndroid) return;
    await _ensureAndroidStoragePermission();
  }

  Future<ExportResult> exportAllDiariesToTxt({
    required void Function(ExportProgress p) onProgress,
    bool reverseOrder = false,
    DateTime? startDate,
    DateTime? endDate,
    int concurrency = 16,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      throw Exception('缺少 user_id，请重新登录');
    }

    onProgress(
      const ExportProgress(current: 0, total: 1, message: '正在同步日记列表...'),
    );
    final syncJson = await _api.sync();
    if (syncJson == null) throw Exception('sync 接口返回为空');

    final diaries = (syncJson['diaries'] as List?) ?? const [];
    final userConfig = (syncJson['user_config'] as Map?) ?? const {};
    final userName = (userConfig['name']?.toString().trim().isNotEmpty ?? false)
        ? userConfig['name'].toString().trim()
        : '用户';

    // 日期范围：包含起止日
    final start = startDate == null
        ? null
        : DateTime(startDate.year, startDate.month, startDate.day);
    final end = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    final ids = <int>[];
    for (final d in diaries) {
      if (d is! Map) continue;
      final id = int.tryParse(d['id']?.toString() ?? '');
      if (id == null) continue;

      // 默认导出全部日记；仅当用户选择了日期范围时才做过滤。
      if (start != null && end != null) {
        DateTime? dt;
        final created = d['createddate'];
        if (created is int) {
          dt = DateTime.fromMillisecondsSinceEpoch(created * 1000);
        } else {
          dt = DateTime.tryParse(created?.toString() ?? '');
        }

        // sync 若缺 createddate（或解析失败），保守策略：仍然纳入导出，避免“选了范围就漏数据”。
        if (dt != null) {
          if (dt.isBefore(start) || dt.isAfter(end)) continue;
        }
      }

      ids.add(id);
    }

    // reverseOrder == true：自旧至新（对齐 aardio：勾选后 totalStr = singleStr ++ totalStr）
    if (reverseOrder) {
      // 修正：先通过 .toList() 创建一个副本列表，断开与原 ids 的视图关联
      ids.setAll(0, ids.reversed.toList());
    }

    final total = ids.length;
    final buffer = StringBuffer();
    final dateFmt = DateFormat('yyyy-MM-dd');

    // 先把总数回传给 UI，让按钮文案能立刻显示 (1/total)
    onProgress(
      ExportProgress(
        current: 0,
        total: total,
        message: total == 0 ? '所选范围内无日记' : '准备开始导出...',
      ),
    );

    // 并发拉取详情，但保持最终输出顺序与 ids 一致。
    final chunks = List<String?>.filled(ids.length, null);
    int done = 0;
    final c = concurrency.clamp(1, 16);

    await _forEachConcurrent<int>(
      ids,
      concurrency: c,
      action: (index, diaryId) async {
        final detailJson = await _api.allByIds(
          userId: userId,
          diaryId: diaryId,
        );
        final detailList = (detailJson?['diaries'] as List?) ?? const [];
        if (detailList.isEmpty || detailList.first is! Map) {
          // 仍然算作“处理完成”，避免进度卡住。
          done++;
          onProgress(ExportProgress(current: done, total: total, message: ''));
          return;
        }

        final detail = detailList.first as Map;
        final created = detail['createddate'];
        final title = detail['title']?.toString() ?? '';
        var content = detail['content']?.toString() ?? '';

        // 替换隐私段
        content = CryptoService.replacePrivacyBlocks(
          content: content,
          userId: userId,
          privacyPattern: AppConstants.privacyPattern,
        );

        // 清理 \r，避免 windows 上重复换行
        content = content.replaceAll('\r', '');

        DateTime? dt;
        if (created is int) {
          dt = DateTime.fromMillisecondsSinceEpoch(created * 1000);
        } else {
          dt = DateTime.tryParse(created?.toString() ?? '');
        }
        final dateLine = dt == null ? '' : dateFmt.format(dt);

        final chunk = StringBuffer()
          ..writeln(dateLine)
          ..writeln(title)
          ..writeln(content)
          ..writeln('————————————————————')
          ..writeln();
        chunks[index] = chunk.toString();

        // 标记已读（失败不影响导出）
        try {
          await _api.updateReadMark(diaryId);
        } catch (_) {}

        done++;
        // UI 不再显示单独的进度文案，只需要 current/total 即可
        onProgress(ExportProgress(current: done, total: total, message: ''));
      },
    );

    for (final s in chunks) {
      if (s == null) continue;
      buffer.write(s);
    }

    final safeName = _sanitizeFileName(userName);

    // 输出路径：
    // - Android：固定到 /storage/emulated/0/你的日记/用户名的日记.txt
    // - 其他平台：应用 documents/你记导出/ 目录
    final file = await _resolveOutputFile(safeName: safeName);
    await file.writeAsString(buffer.toString(), flush: true);

    return ExportResult(filePath: file.path, exportedCount: total);
  }

  /// 导出所有图片到导出目录下的“图片/”子文件夹。
  ///
  /// 逻辑对齐 aardio：sync 返回 images 表，取最大 image_id 作为总量，逐个尝试下载；不存在则跳过。
  Future<ExportResult> exportAllImages({
    required void Function(ExportProgress p) onProgress,
    int concurrency = 16,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      throw Exception('缺少 user_id，请重新登录');
    }

    onProgress(
      const ExportProgress(current: 0, total: 0, message: '正在获取图片总数...'),
    );

    final syncJson = await _api.sync();
    if (syncJson == null) throw Exception('sync 接口返回为空');

    final images = (syncJson['images'] as List?) ?? const [];
    int maxImageId = 0;
    for (final img in images) {
      if (img is! Map) continue;
      final v = int.tryParse(img['image_id']?.toString() ?? '');
      if (v != null && v > maxImageId) maxImageId = v;
    }

    final dir = await _resolveImagesDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    if (maxImageId <= 0) {
      onProgress(
        const ExportProgress(current: 0, total: 0, message: '未发现可导出的图片'),
      );
      return ExportResult(filePath: dir.path, exportedCount: 0);
    }

    int saved = 0;
    int done = 0;
    final ids = List<int>.generate(maxImageId, (i) => i + 1);
    final c = concurrency.clamp(1, 16);

    await _forEachConcurrent<int>(
      ids,
      concurrency: c,
      action: (_, imageId) async {
        // message 保留当前正在处理的 imageId；current 改为“已处理数量”，保证进度单调递增。
        onProgress(
          ExportProgress(
            current: done,
            total: maxImageId,
            message: '正在保存图 $imageId',
          ),
        );

        final file = File(_joinPath([dir.path, '图$imageId.jpg']));
        if (await file.exists()) {
          done++;
          return;
        }

        final bytes = await _api.downloadImageBytes(
          userId: userId,
          imageId: imageId,
        );
        if (bytes == null || bytes.isEmpty) {
          done++;
          return;
        }

        await file.writeAsBytes(bytes, flush: true);
        saved++;
        done++;
      },
    );

    // 收尾刷新一次进度
    onProgress(ExportProgress(current: done, total: maxImageId, message: ''));

    return ExportResult(filePath: dir.path, exportedCount: saved);
  }

  String _sanitizeFileName(String input) {
    // Windows/Android 通用的非法字符过滤，并去掉换行/制表符
    return input
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 拼接路径：Windows 使用 `\\`，其他平台使用 `/`。
  ///
  /// 说明：这里不依赖 `package:path`，避免引入额外依赖；同时确保
  /// Windows 下展示/返回的路径符合系统默认分隔符。
  String _joinPath(List<String> parts) {
    // 注意：Dart 字符串里 "\\" 表示单个反斜杠字符。
    // 之前使用 raw string r"\\" 会产生两个反斜杠字符，导致路径里出现 \\\\。
    final sep = Platform.isWindows ? '\\' : '/';
    final cleaned = <String>[];
    for (final p in parts) {
      final s = p.toString();
      if (s.isEmpty) continue;

      // 统一去掉两端分隔符，避免出现重复的 // 或 \\\\。
      final trimmed = s.replaceAll(RegExp(r'^[\\/]+|[\\/]+$'), '');
      if (trimmed.isEmpty) continue;
      cleaned.add(trimmed);
    }

    // 若 parts 为空或全部为空字符串，返回空。
    if (cleaned.isEmpty) return '';

    // 特殊处理：第一个 part 可能是绝对路径（Windows: C:\\xxx / \Server\Share；
    // POSIX: /xxx）。上面 trim 会去掉前导分隔符，因此需要把原始第一个 part 的
    // “根信息”补回去。
    final firstRaw = parts.isEmpty ? '' : parts.first;
    if (firstRaw.startsWith(r'\\')) {
      // UNC 路径：\\Server\Share\...
      return '\\\\${cleaned.join(sep)}';
    }
    if (firstRaw.contains(':\\') || firstRaw.contains(':/')) {
      // Windows 盘符路径：C:\\...
      // cleaned[0] 里应包含盘符，例如 C:，不需要额外补 sep。
      return cleaned.join(sep);
    }
    if (!Platform.isWindows && firstRaw.startsWith('/')) {
      // POSIX 绝对路径
      return '/${cleaned.join(sep)}';
    }
    return cleaned.join(sep);
  }

  Future<Directory> _resolveNonAndroidExportBaseDir() async {
    final doc = await getApplicationDocumentsDirectory();
    final base = Directory(_joinPath([doc.path, '你记导出']));
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return base;
  }

  Future<File> _resolveOutputFile({required String safeName}) async {
    if (Platform.isAndroid) {
      await _ensureAndroidStoragePermission();

      final dir = Directory('/storage/emulated/0/你的日记');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/$safeName的日记.txt');
    }

    // 非 Android：导出到 documents/你记导出/
    final base = await _resolveNonAndroidExportBaseDir();
    return File(_joinPath([base.path, '$safeName的日记.txt']));
  }

  Future<Directory> _resolveImagesDir() async {
    if (Platform.isAndroid) {
      await _ensureAndroidStoragePermission();
      final base = Directory('/storage/emulated/0/你的日记');
      if (!await base.exists()) {
        await base.create(recursive: true);
      }
      return Directory('${base.path}/图片');
    }

    // 非 Android：导出到 documents/你记导出/图片
    final base = await _resolveNonAndroidExportBaseDir();
    return Directory(_joinPath([base.path, '图片']));
  }

  Future<void> _ensureAndroidStoragePermission() async {
    // Android 11+ 若要写入 /storage/emulated/0 根目录下的自定义目录，通常需要“所有文件访问权限”。
    // 如果用户拒绝，则降级尝试普通存储权限。
    if (!Platform.isAndroid) return;

    // 先请求 MANAGE_EXTERNAL_STORAGE
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return;

    // 再尝试传统 storage 权限（在部分系统/机型上仍可能生效）
    final storage = await Permission.storage.request();
    if (storage.isGranted) return;

    throw Exception('需要存储权限才能导出到 /storage/emulated/0/你的日记/');
  }
}
