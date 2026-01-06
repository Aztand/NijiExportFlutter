import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../services/export_service.dart';

enum _ExportJob { none, diaries, images }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // 1. 将变量定义在类级别，这样 build 方法才能访问到它们
  String _username = "加载中...";
  String _userdescrp = "三叶，你在哪儿？";
  String? _avatarUrl; // 使用 String? 表示可能为空

  // 两个导出按钮需要互不干扰：分别维护状态与进度
  _ExportJob _exportJob = _ExportJob.none;

  int _diaryNow = 0;
  int _diaryTotal = 0;
  String _diaryMessage = '';

  int _imageNow = 0;
  int _imageTotal = 0;
  String _imageMessage = '';

  // 日期范围（包含起止日）
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // aardio 对齐：“日记自旧至新”
  bool _oldToNew = false;

  bool get _isBusy => _exportJob != _ExportJob.none;

  Future<void> _openExportLocation(String filePath) async {
    final isDir = await FileSystemEntity.isDirectory(filePath);
    final dirPath = isDir ? filePath : File(filePath).parent.path;
    try {
      if (Platform.isWindows) {
        // 统一使用 Windows 风格分隔符，避免 explorer 对混合分隔符/转义产生误判。
        final winDirPath = dirPath.replaceAll('/', '\\');
        final winFilePath = filePath.replaceAll('/', '\\');

        // - 如果是目录：直接打开目录
        // - 如果是文件：在资源管理器中选中文件
        // explorer 参数中 /select, 和 path 必须是同一个参数，否则会出现打开失败/不选中。
        // 注意：Process.start 的 args 不需要手动加引号；把引号作为参数内容传入会导致 explorer 解析失败。
        if (isDir) {
          await Process.start('explorer.exe', [winDirPath], runInShell: true);
        } else {
          await Process.start('explorer.exe', ['/select,', winFilePath]);
        }
      } else if (Platform.isMacOS) {
        await Process.start('open', [dirPath], runInShell: true);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [dirPath], runInShell: true);
      }
    } catch (_) {
      // 打开失败不影响流程
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  // 2. 修正后的读取逻辑
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();

    // 确保使用 setState 来通知界面刷新
    setState(() {
      _username = prefs.getString('username') ?? "立花泷";
      _userdescrp = prefs.getString('description') ?? "三叶，你在哪儿？";
      _avatarUrl = prefs.getString('avatar_url'); // 从本地读取头像地址
    });
  }

  void _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_login', false);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Future<void> _startExport() async {
    if (_isBusy) return;
    setState(() {
      _exportJob = _ExportJob.diaries;
      _diaryNow = 0;
      _diaryTotal = 0;
      _diaryMessage = '准备中...';
    });

    try {
      final service = ExportService();

      // 需求：安卓的索要权限放在点击按钮后立刻要，避免网络等待后才弹权限导致误拒绝
      await service.ensureExportPermissionIfNeeded();

      final result = await service.exportAllDiariesToTxt(
        startDate: _rangeStart,
        endDate: _rangeEnd,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _diaryNow = p.current;
            _diaryTotal = p.total;
            _diaryMessage = p.message;
          });
        },
        // UI 文案为“日记自旧至新”，这里用 reverseOrder 让导出顺序对齐
        reverseOrder: _oldToNew,
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出完成'),
          content: SelectableText(
            '已导出 ${result.exportedCount} 篇日记\n\n文件位置：\n${result.filePath}',
          ),
          actions: [
            if (!Platform.isAndroid)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _openExportLocation(result.filePath);
                },
                child: const Text('打开文件夹'),
              ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: File(result.filePath).parent.path),
                );
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('已复制导出目录路径')));
              },
              child: const Text('复制路径'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出失败'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportJob = _ExportJob.none;
        });
      }
    }
  }

  Future<void> _startExportImages() async {
    if (_isBusy) return;
    setState(() {
      _exportJob = _ExportJob.images;
      _imageNow = 0;
      _imageTotal = 0;
      _imageMessage = '准备中...';
    });

    try {
      final service = ExportService();

      // 同样要在按钮点击后立刻申请权限
      await service.ensureExportPermissionIfNeeded();

      final result = await service.exportAllImages(
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _imageNow = p.current;
            _imageTotal = p.total;
            _imageMessage = p.message;
          });
        },
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('图片导出完成'),
          content: SelectableText(
            '已导出 ${result.exportedCount} 张图片\n\n目录：\n${result.filePath}',
          ),
          actions: [
            if (!Platform.isAndroid)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _openExportLocation(result.filePath);
                },
                child: const Text('打开文件夹'),
              ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: result.filePath));
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('已复制导出目录路径')));
              },
              child: const Text('复制路径'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('图片导出失败'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportJob = _ExportJob.none;
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: _rangeStart ?? DateTime(now.year, now.month, 1),
      end: _rangeEnd ?? now,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (picked == null) return;
    setState(() {
      _rangeStart = picked.start;
      _rangeEnd = picked.end;
    });
  }

  // 默认不打扰普通用户：把日期范围/排序等进阶选项放到弹层里
  Future<void> _openAdvancedOptionsSheet() async {
    await showModalBottomSheet(
      context: context,
      // 需求：卡片背景随系统深色/浅色模式变化
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2B2B2B)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // 修复：sheet 内 Checkbox 勾选状态不更新（父级 setState 不会让 bottomSheet 重建）
        bool sheetOldToNew = _oldToNew;
        DateTime? sheetStart = _rangeStart;
        DateTime? sheetEnd = _rangeEnd;

        return StatefulBuilder(
          builder: (ctx, sheetSetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final fg = isDark ? Colors.white : Colors.black;
            final sub = isDark ? Colors.white70 : Colors.black54;

            final rangeText = (sheetStart == null || sheetEnd == null)
                ? '全部日记（默认）'
                : '${sheetStart!.toIso8601String().substring(0, 10)} ~ ${sheetEnd!.toIso8601String().substring(0, 10)}';

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '高级选项',
                      style: TextStyle(
                        color: fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('日期范围', style: TextStyle(color: fg)),
                      subtitle: Text(rangeText, style: TextStyle(color: sub)),
                      trailing: TextButton(
                        onPressed: _isBusy
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _pickDateRange();
                              },
                        child: const Text('选择'),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('排序', style: TextStyle(color: fg)),
                      subtitle: Text('日记自旧至新', style: TextStyle(color: sub)),
                      trailing: Checkbox(
                        value: sheetOldToNew,
                        onChanged: _isBusy
                            ? null
                            : (v) {
                                sheetSetState(() {
                                  sheetOldToNew = v ?? false;
                                });
                                setState(() {
                                  _oldToNew = sheetOldToNew;
                                });
                              },
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isBusy
                                ? null
                                : () {
                                    sheetSetState(() {
                                      sheetStart = null;
                                      sheetEnd = null;
                                    });
                                    setState(() {
                                      _rangeStart = null;
                                      _rangeEnd = null;
                                    });
                                  },
                            child: Text('清除日期范围', style: TextStyle(color: fg)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('完成'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  // 这里不再使用 const，因为 _avatarUrl 是动态的
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white10,
                    // 判断头像地址是否存在
                    backgroundImage:
                        (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                        ? NetworkImage(_avatarUrl!)
                        : null,
                    // 如果没有头像地址，则显示图标
                    child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                        ? const Icon(
                            Icons.person,
                            size: 35,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _username,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userdescrp,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isBusy ? null : _openAdvancedOptionsSheet,
                icon: const Icon(Icons.tune, color: Colors.white70, size: 18),
                label: const Text(
                  '高级选项',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const Spacer(),
            Center(
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _startExport,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(
                    _exportJob == _ExportJob.diaries
                        ? (_diaryTotal <= 0
                              ? (_diaryMessage.isNotEmpty
                                    ? _diaryMessage
                                    : '正在统计总量...')
                              : '正在导出（$_diaryNow/$_diaryTotal）')
                        : "导出日记",
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _startExportImages,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _exportJob == _ExportJob.images
                        ? (_imageTotal <= 0
                              ? (_imageMessage.isNotEmpty
                                    ? _imageMessage
                                    : '正在统计总量...')
                              : '正在导出（$_imageNow/$_imageTotal）')
                        : '导出图片',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
