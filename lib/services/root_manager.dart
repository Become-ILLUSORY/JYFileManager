// Root 权限管理器
//
// 通过调用 `su -c` 探测与请求 root（Magisk / KernelSU / APatch 均提供 su）。
// 本应用不内置任何提权实现，只作为「客户端」向用户已安装的 root 方案申请授权；
// 用户可在 Magisk / KernelSU 的超级用户列表里授予或撤销。
import 'dart:async';
import 'dart:io';

/// Root 可用状态
enum RootStatus {
  /// 尚未检测
  unknown,

  /// 设备没有 root（无 su 命令，或用户拒绝）
  unavailable,

  /// 有 root 且已授权
  granted,

  /// 有 su 但被拒绝
  denied,
}

/// Root 管理器（单例）
class RootManager {
  RootManager._();
  static final RootManager instance = RootManager._();

  RootStatus _status = RootStatus.unknown;
  RootStatus get status => _status;

  bool get isGranted => _status == RootStatus.granted;

  /// 当前使用的 root 方案名（Magisk / KernelSU / APatch / su）
  String? _flavor;
  String? get flavor => _flavor;

  /// su 二进制路径
  String? _suPath;
  String? get suPath => _suPath;

  final _controller = StreamController<RootStatus>.broadcast();

  /// 状态变化流，UI 可监听刷新
  Stream<RootStatus> get changes => _controller.stream;

  /// 探测 root 状态。
  ///
  /// [request] 为 true 时会真正执行 `su`，可能触发授权弹窗；
  /// 为 false 时只检查 su 是否存在，不打扰用户。
  Future<RootStatus> detect({bool request = true}) async {
    _suPath = await _findSu();
    if (_suPath == null) {
      _set(RootStatus.unavailable);
      return _status;
    }

    if (!request) {
      // 只报告「有 su」，但尚未确认是否已授权
      _set(_status == RootStatus.granted
          ? RootStatus.granted
          : RootStatus.unknown);
      return _status;
    }

    try {
      final r = await Process.run(_suPath!, ['-c', 'id'])
          .timeout(const Duration(seconds: 25));
      final out = '${r.stdout}${r.stderr}';
      if (r.exitCode == 0 && out.contains('uid=0')) {
        _flavor = await _detectFlavor();
        _set(RootStatus.granted);
      } else {
        _set(RootStatus.denied);
      }
    } on TimeoutException {
      // 授权弹窗超时未响应
      _set(RootStatus.denied);
    } catch (_) {
      _set(RootStatus.denied);
    }
    return _status;
  }

  /// 以 root 执行命令
  Future<ProcessResult> exec(String command) async {
    final su = _suPath ?? await _findSu();
    if (su == null) {
      throw const ProcessException('su', [], '设备未提供 su 命令（未安装 root）');
    }
    return Process.run(su, ['-c', command]);
  }

  /// 以 root 执行并返回 stdout
  Future<String> execOut(String command) async {
    final r = await exec(command);
    return r.stdout.toString();
  }

  /// 放弃已缓存的授权状态（例如用户在 root 管理器中撤销后）
  void reset() {
    _status = RootStatus.unknown;
    _flavor = null;
    _controller.add(_status);
  }

  void _set(RootStatus s) {
    _status = s;
    _controller.add(s);
  }

  /// 查找 su 可执行文件
  Future<String?> _findSu() async {
    const candidates = [
      '/system/bin/su',
      '/system/xbin/su',
      '/sbin/su',
      '/su/bin/su',
      '/debug_ramdisk/su',
      '/magisk/.core/bin/su',
      '/data/adb/ksu/bin/su',
      '/data/adb/ap/bin/su',
    ];
    for (final p in candidates) {
      try {
        if (await File(p).exists()) return p;
      } catch (_) {}
    }
    // 退回 PATH 查找
    try {
      final r = await Process.run('which', ['su']);
      final out = r.stdout.toString().trim();
      if (r.exitCode == 0 && out.isNotEmpty) return out.split('\n').first;
    } catch (_) {}
    return null;
  }

  /// 识别 root 方案
  Future<String> _detectFlavor() async {
    try {
      final ksu = await execOut('test -d /data/adb/ksu && echo ksu');
      if (ksu.contains('ksu')) return 'KernelSU';
    } catch (_) {}
    try {
      final ap = await execOut('test -d /data/adb/ap && echo ap');
      if (ap.contains('ap')) return 'APatch';
    } catch (_) {}
    try {
      final magisk = await execOut('magisk -V 2>/dev/null');
      if (magisk.trim().isNotEmpty) return 'Magisk ${magisk.trim()}';
    } catch (_) {}
    try {
      final ksuV = await execOut('ksud -V 2>/dev/null');
      if (ksuV.trim().isNotEmpty) return 'KernelSU';
    } catch (_) {}
    return 'su';
  }
}
