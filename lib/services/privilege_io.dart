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

import 'app_settings.dart';

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

  /// 面向 UI 的简短标签（顶栏 / 设置项右侧展示）
  String get label {
    if (rootActive) return flavor?.isNotEmpty == true ? 'Root · $flavor' : 'Root';
    if (shizukuActive) {
      return flavor?.isNotEmpty == true ? 'Shizuku $flavor' : 'Shizuku';
    }
    return '未启用';
  }

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

  /// 是否已从 AppSettings 载入过用户选择
  bool _restored = false;

  /// Root 探测结果缓存（避免每次 refresh 都 fork su）
  bool _rootCached = false;
  String? _rootFlavor;

  /// 非交互探测失败的缓存时间戳。
  ///
  /// 未授权的 su 每次探测都要等超时（6 秒），而 SmartFs 在每次权限错误时都会
  /// 询问一次；没有这个缓存，浏览一个无权限的目录会反复卡 6 秒。
  DateTime? _rootFailedAt;
  static const _rootFailTtl = Duration(seconds: 20);

  /// 从设置里恢复用户的提权选择（App 启动时调用一次）。
  ///
  /// 用户手动选了 Root / Shizuku 就应当记住，下次启动直接按该通道探测，
  /// 不再要求用户重新授权一次。
  ///
  /// 即使用户从未手动选择过，也会做一次静默探测：设备已 root 且 su 已授权时
  /// 应当直接可用，而不是让用户先去设置里点一次「授权」。
  Future<void> restorePreference() async {
    if (_restored) return;
    _restored = true;
    final saved = AppSettings.instance.privilegeMode;
    _preferred = switch (saved) {
      1 => PrivilegeMode.root,
      2 => PrivilegeMode.shizuku,
      _ => PrivilegeMode.none,
    };
    // 静默探测（已授权的 su 不会弹窗；未授权时短超时，不拖慢启动）
    await refresh();
  }

  final _controller = StreamController<PrivilegeStatus>.broadcast();

  /// 状态变化流，UI 可监听刷新
  Stream<PrivilegeStatus> get changes => _controller.stream;

  bool get isActive => _status.active;

  /// 探测当前可用的提权通道。
  ///
  /// [interactive] 为 true 时允许触发授权弹窗（Root 的 su 提示 / Shizuku 的授权页）。
  /// 当用户已在设置里指定了通道时，优先探测该通道。
  Future<PrivilegeStatus> refresh({bool interactive = false}) async {
    // 0. 用户已指定通道：优先按它探测，成功即用
    if (_preferred == PrivilegeMode.root) {
      final r = await _probeRoot(interactive: interactive);
      if (r.active) {
        _set(r);
        return _status;
      }
      final s = await _probeShizuku(interactive: false);
      _set(PrivilegeStatus(
        mode: PrivilegeMode.none,
        active: false,
        detail: r.detail,
        shizukuInstalled: s.shizukuInstalled,
      ));
      return _status;
    }
    if (_preferred == PrivilegeMode.shizuku) {
      final s = await _probeShizuku(interactive: interactive);
      if (s.active) {
        _set(s);
        return _status;
      }
      // 用户指定 Shizuku 但不可用：顺带探测 Root 以便 UI 提示可切换
      await _probeRoot(interactive: false);
      _set(PrivilegeStatus(
        mode: PrivilegeMode.none,
        active: false,
        detail: s.detail,
        shizukuInstalled: s.shizukuInstalled,
      ));
      return _status;
    }

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

  /// 启用指定的提权方式（会触发授权请求），并持久化用户选择
  Future<PrivilegeStatus> enable(PrivilegeMode mode) async {
    _preferred = mode;
    _restored = true;
    // 用户主动点授权：清掉失败缓存，让这次是真正的新探测（会弹授权框）
    _rootFailedAt = null;
    AppSettings.instance.setPrivilegeMode(switch (mode) {
      PrivilegeMode.root => 1,
      PrivilegeMode.shizuku => 2,
      PrivilegeMode.none => 0,
    });
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
    _restored = true;
    AppSettings.instance.setPrivilegeMode(0);
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
    _rootCached = false;
    _rootFlavor = null;
    _rootFailedAt = null;
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
    // 已确认过 Root 可用就直接复用，避免反复 fork su
    if (_rootCached) {
      return PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: true,
        detail: '已获得 Root 权限',
        flavor: _rootFlavor,
      );
    }
    // 刚失败过就先别急着再 fork 一次 su（未授权时每次都要等满超时）
    final failedAt = _rootFailedAt;
    if (!interactive &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < _rootFailTtl) {
      return const PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: false,
        detail: '检测到 su，点此授权 Root',
      );
    }
    // 非交互也要真探测：已授权的 su 不会弹窗；未授权时超时短一些避免拖慢启动。
    // 用户既然开了 Root 提权，就不该被"静默失败"挡住。
    final timeout = interactive
        ? const Duration(seconds: 25)
        : const Duration(seconds: 6);
    try {
      final r = await Process.run(su, ['-c', 'id']).timeout(timeout);
      final out = '${r.stdout}${r.stderr}';
      if (r.exitCode == 0 && out.contains('uid=0')) {
        final flavor = await _detectFlavor(su);
        _rootCached = true;
        _rootFlavor = flavor;
        _rootFailedAt = null;
        return PrivilegeStatus(
          mode: PrivilegeMode.root,
          active: true,
          detail: '已获得 Root 权限',
          flavor: flavor,
        );
      }
      _rootFailedAt = DateTime.now();
      return const PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: false,
        detail: 'Root 授权被拒绝，请在 Root 管理器中放行',
      );
    } on TimeoutException {
      _rootFailedAt = DateTime.now();
      return PrivilegeStatus(
        mode: PrivilegeMode.root,
        active: false,
        detail: interactive ? '等待 Root 授权超时，请重试' : '检测到 su，点此授权 Root',
      );
    } catch (e) {
      _rootFailedAt = DateTime.now();
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
