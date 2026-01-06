// 条件导入：
// - Web/其他非 io 环境：使用 stub（no-op）
// - IO 环境（Windows/macOS/Linux/Android/iOS）：进入 io 实现，内部再按 Platform 判断是否 Windows
export 'window_manager_initializer_stub.dart'
    if (dart.library.io) 'window_manager_initializer_io.dart';
