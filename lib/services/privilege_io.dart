// 提权层（原生实现）
//
// 统一封装两种特权通道：
//   1. Root  —— 调用系统上的 `su`（Magisk / KernelSU / APatch 提供）
//   2. Shizuku —— 通过原生桥调用用户已授权的 Shizuku 服务（adb 级权限）
//
// 本应用不实现任何提权手段，只作为客户端向用户已有的方案申请授权，
// 用户可随时在 Root 管理器 / Shizuku 应用内撤销。
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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
    this.shizukuInstalled = false,
  });

  final PrivilegeMode mode;

  /// 当前提权通道是否可用（可立即执行特权命令）
  final bool active;

  /// 面向用户的说明文字
  final String detail;

  /// Root 方案名（Magisk 27.0 / KernelSU / APatch）或 Shizuku 版本
  final String? flavor;

  /// 设备是否安装了 Shizuku 管理器
  final bool shizukuInstalled;

  bool get rootActive => active && mode == PrivilegeMode.root;
  bool get shizukuActive => active && mode == PrivilegeMode.shizuku;

  PrivilegeStatus copyWith({
    PrivilegeMode? mode,
    bool? active,
    String? detail,
    String? flavor,
    bool? shizukuInstalled,
  }) {
    return PrivilegeStatus(
      mode: mode ?? this.mode,
      active: active ?? this.active,
      detail: detail ?? this.detail,
      flavor: flavor ?? this.flavor,
      shizukuInstalled: shizukuInstalled ?? this.shizukuInstalled,
    );
  }
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

  /// 合并输出（用于判断命令是否成功）
  String get combined => '$stdout$stderr';
}

/// 提权管理器（单例）
class PrivilegeManager {
  PrivilegeManager._();
  static final PrivilegeManager instance = PrivilegeManager._();

  static const MethodChannel _shizukuChannel =
      MethodChannel('jyfilemanager/privilege');

  PrivilegeStatus _status = const PrivilegeStatus();
  PrivilegeStatus get status => _status;

  /// 用户偏好的提权方式（none 表示自动）
  PrivilegeMode _preferred = PrivilegeMode.none;
  PrivilegeMode get preferred => _preferred;

  final _controller = StreamController<PrivilegeStatus>.broadcast();

  /// 状态变化流，UI 可监听刷新
  Stream<PrivilegeStatus> get changes => _controller.stream;

  bool get isActive => _status.active;

  /// 探测当前可用的提权通道。
  ///
  /// [interactive] 为 true 时允许触发授权弹窗（Root 的 su 提示 / Shizuku 的授权页）。
  Future<PrivilegeStatus> refresh({bool interactive = false}) async {
    // 1. 先看 Root：su 存在且能拿到 uid=0
    final root = await _probeRoot(interactive: interactive);
    if (root.active) {
      _set(root);
      return _status;
    }

    // 2. 再看 Shizuku
    final shizuku = await _probeShizuku(interactive: interactive);
    if (shizuku.active) {
      _set(shizuku);
      return _status;
    }

    // 3. 都不行：保留诊断信息，便于 UI 给出准确的引导
    _set(
      PrivilegeStatus(
        mode: PrivilegeMode.none,
        active: false,
        detail: root.detail,
        shizukuInstalled: shizuku.shizukuInstalled,
      ),
    );
    return _status;
  }

  /// 启用指定的提权方式（会触发授权请求）
  Future<PrivilegeStatus> enable(PrivilegeMode mode) async {
    _preferred = mode;
    switch (mode) {
      case PrivilegeMode.root:
        _set(await _probeRoot(interactive: true));
      case PrivilegeMode.shizuku:
        _set(await _probeShizuku(interactive: true));
      case PrivilegeMode.none:
        await disable();
    }
    return _status;
  }

  /// 关闭提权（仅清除本地状态，不撤销系统里的授权）
  Future<void> disable() async {
    _preferred = PrivilegeMode.none;
    _set(const PrivilegeStatus());
  }

  /// 以特权身份执行命令。
  ///
  /// 优先使用当前已激活的通道；若都没激活则抛 [PrivilegeUnavailable]，
  /// 由上层决定是提示用户还是降级为普通访问。
  Future<ExecResult> exec(String command) async {
    switch (_status.mode) {
      case PrivilegeMode.root:
        if (_status.active) return _execRoot(command);
      case PrivilegeMode.shizuku:
        if (_status.active) return _execShizuku(command);
      case PrivilegeMode.none:
        break;
    }
    // 状态未知时先探测一次（不打扰用户）
    await refresh();
    if (_status.active) return exec(command);
    throw const PrivilegeUnavailable('尚未获得提权，无法访问该位置');
  }

  /// 清除缓存，下次重新探测
  Future<void> reset() async {
    _status = const PrivilegeStatus();
    _controller.add(_status);
  }

  // ---------------------------------------------------------------- Root

  /// 查找 su 二进制
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
    try {
      final r = await Process.run('which', ['su']);
      final out = r.stdout.toString().trim();
      if (r.exitCode == 0 && out.isNotEmpty) return out.split('\n').first;
    } catch (_) {}
    return null;
  }

  Future<PrivilegeStatus> _probeRoot({required bool interactive}) async {
    final su = await _findSu();
    if (su == null) {
      return const PrivilegeStatus(
        mode: PrivilegeMode.none,
        active: false,
        detail: '设备未安装 Root（未找到 su 命令）',
      );
    }
    if (!interactive) {
      // 非交互探测：不执行 su，避免弹出授权框
      return PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: false,
        detail: '检测到 su，可在设置中授权',
        flavor: null,
      );
    }
    try {
      final r = await Process.run(su, ['-c', 'id'])
          .timeout(const Duration(seconds: 25));
      final out = '${r.stdout}${r.stderr}';
      if (r.exitCode == 0 && out.contains('uid=0')) {
        final flavor = await _detectFlavor(su);
        return PrivilegeStatus(
          mode: PrivilegeMode.root,
          active: true,
          detail: '已获得 Root 权限',
          flavor: flavor,
        );
      }
      return const PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: false,
        detail: 'Root 授权被拒绝，请在 Root 管理器中放行',
      );
    } on TimeoutException {
      return const PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: false,
        detail: '等待 Root 授权超时，请重试',
      );
    } catch (e) {
      return PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: false,
        detail: 'Root 探测失败：$e',
      );
    }
  }

  /// 识别 root 方案
  Future<String> _detectFlavor(String su) async {
    Future<String> run(String cmd) async {
      try {
        final r = await Process.run(su, ['-c', cmd])
            .timeout(const Duration(seconds: 10));
        return r.stdout.toString().trim();
      } catch (_) {
        return '';
      }
    }

    final ksu = await run('test -d /data/adb/ksu && echo yes');
    if (ksu.contains('yes')) {
      final v = await run('ksud -V 2>/dev/null');
      return v.isEmpty ? 'KernelSU' : 'KernelSU $v';
    }
    final ap = await run('test -d /data/adb/ap && echo yes');
    if (ap.contains('yes')) return 'APatch';
    final magisk = await run('magisk -V 2>/dev/null');
    if (magisk.isNotEmpty) return 'Magisk $magisk';
    return 'su';
  }

  Future<ExecResult> _execRoot(String command) async {
    final su = await _findSu();
    if (su == null) {
      return const ExecResult(ok: false, error: 'no_su');
    }
    try {
      final r = await Process.run(su, ['-c', command])
          .timeout(const Duration(seconds: 30));
      return ExecResult(
        ok: r.exitCode == 0,
        exitCode: r.exitCode,
        stdout: r.stdout.toString(),
        stderr: r.stderr.toString(),
      );
    } catch (e) {
      return ExecResult(ok: false, error: '$e');
    }
  }

  // ------------------------------------------------------------- Shizuku

  Future<PrivilegeStatus> _probeShizuku({required bool interactive}) async {
    try {
      var raw = await _shizukuChannel.invokeMethod<dynamic>('status');
      var map = _asMap(raw);
      var available = map['available'] == true;
      var granted = map['granted'] == true;
      final installed = map['installed'] == true;

      if (available && !granted && interactive) {
        // 触发授权请求；结果由原生侧监听器异步返回
        raw = await _shizukuChannel.invokeMethod<dynamic>('request');
        map = _asMap(raw);
        available = map['available'] == true;
        granted = map['granted'] == true;
      }

      if (available && granted) {
        final v = map['version'];
        return PrivilegeStatus(
          mode: PrivilegeMode.shizuku,
          active: true,
          detail: '已获得 Shizuku 权限',
          flavor: v == null ? 'Shizuku' : 'Shizuku $v',
          shizukuInstalled: true,
        );
      }

      if (!available) {
        return PrivilegeStatus(
          mode: PrivilegeMode.none,
          active: false,
          detail: installed
              ? 'Shizuku 已安装但服务未运行，请先在 Shizuku 应用中启动'
              : '未检测到 Shizuku',
          shizukuInstalled: installed,
        );
      }

      return const PrivilegeStatus(
        mode: PrivilegeMode.shizuku,
        active: false,
        detail: 'Shizuku 权限被拒绝，请在 Shizuku 应用中允许本应用',
        shizukuInstalled: true,
      );
    } on MissingPluginException {
      return const PrivilegeStatus(
        mode: PrivilegeMode.none,
        active: false,
        detail: '当前平台不支持 Shizuku',
      );
    } catch (e) {
      return PrivilegeStatus(
        mode: PrivilegeMode.none,
        active: false,
        detail: 'Shizuku 探测失败：$e',
      );
    }
  }

  Future<ExecResult> _execShizuku(String command) async {
    try {
      final raw = await _shizukuChannel
          .invokeMethod<dynamic>('exec', {'command': command});
      final map = _asMap(raw);
      if (map['ok'] == true) {
        return ExecResult(
          ok: (map['code'] as int? ?? 0) == 0,
          exitCode: map['code'] as int? ?? -1,
          stdout: '${map['stdout'] ?? ''}',
          stderr: '${map['stderr'] ?? ''}',
        );
      }
      return ExecResult(ok: false, error: '${map['error'] ?? 'unknown'}');
    } catch (e) {
      return ExecResult(ok: false, error: '$e');
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry('$k', v));
    }
    return const {};
  }

  void _set(PrivilegeStatus s) {
    _status = s;
    _controller.add(s);
  }
}

/// 未获得提权时抛出
class PrivilegeUnavailable implements Exception {
  const PrivilegeUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
