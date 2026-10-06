// 提权层（Web 桩实现：浏览器无法执行特权命令）

/// 提权方式
enum PrivilegeMode {
  /// 未启用任何提权
  none,

  /// Root（Magisk / KernelSU / APatch 的 su）
  root,

  /// Shizuku（adb 调试授权）
  shizuku,
}

/// 提权状态
class PrivilegeStatus {
  const PrivilegeStatus({
    this.mode = PrivilegeMode.none,
    this.active = false,
    this.detail = '',
    this.flavor,
  });

  final PrivilegeMode mode;

  /// 当前提权通道是否可用
  final bool active;

  /// 面向用户的说明
  final String detail;

  /// Root 方案名 / Shizuku 版本描述
  final String? flavor;

  bool get rootActive => active && mode == PrivilegeMode.root;
  bool get shizukuActive => active && mode == PrivilegeMode.shizuku;
}

/// 特权命令执行结果
class ExecResult {
  const ExecResult({
    required this.ok,
    this.exitCode = -1,
    this.stdout = '',
    this.stderr = '',
    this.error,
  });

  final bool ok;
  final int exitCode;
  final String stdout;
  final String stderr;
  final String? error;
}

/// Web 上提权不可用，全部返回「未启用」。
class PrivilegeManager {
  PrivilegeManager._();
  static final PrivilegeManager instance = PrivilegeManager._();

  PrivilegeStatus get status => const PrivilegeStatus();

  /// 用户偏好的提权方式
  PrivilegeMode get preferred => PrivilegeMode.none;

  /// 当前提权通道是否可用
  bool get isActive => false;

  Future<PrivilegeStatus> refresh({bool interactive = false}) async => status;

  Future<PrivilegeStatus> enable(PrivilegeMode mode) async => status;

  Future<void> disable() async {}

  Future<ExecResult> exec(String command) async => const ExecResult(
        ok: false,
        error: 'unsupported_platform',
      );
}
