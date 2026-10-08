// 智能文件系统：普通访问失败时自动尝试提权
import 'dart:async';
import 'dart:typed_data';

import '../../core/models/file_item.dart';
import '../app_settings.dart';
import '../privilege.dart';
import 'local_fs.dart';
import 'root_fs.dart';
import 'vfs.dart';

/// 智能文件系统。
///
/// 对上层呈现为一个普通 [Vfs]：优先用常规 API 访问，
/// 一旦遇到「权限不足」且用户已开启提权，则自动改用特权通道重试。
///
/// 这样 UI 层完全不需要关心当前是普通模式、Root 还是 Shizuku。
class SmartFs extends Vfs {
  SmartFs._();
  static final SmartFs instance = SmartFs._();

  final LocalFs _local = LocalFs.instance;
  final RootFs _root = RootFs.instance;

  /// 是否启用自动回退（直接读用户设置，避免两份状态不同步）
  bool get autoFallback => AppSettings.instance.autoFallback;

  /// 最近一次操作是否走了特权通道（用于 UI 显示角标）
  bool lastUsedPrivilege = false;

  @override
  String get schemeName => '智能';

  @override
  String get rootPath => _local.rootPath;

  /// 判断异常是否属于「权限不足」
  static bool isPermissionError(Object e) {
    if (e is PermissionException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('permission denied') ||
        s.contains('eacces') ||
        s.contains('operation not permitted') ||
        s.contains('权限');
  }

  /// 提权是否可用
  Future<bool> privilegeReady() async {
    final s = await PrivilegeManager.instance.refresh();
    return s.active;
  }

  /// 包装：先常规访问，权限不足时回退到特权通道
  Future<T> _guard<T>(Future<T> Function() normal, Future<T> Function() privileged) async {
    try {
      lastUsedPrivilege = false;
      return await normal();
    } catch (e) {
      if (!isPermissionError(e)) rethrow;
      if (!autoFallback) {
        throw PermissionException('没有访问权限，可在设置中开启 Root 或 Shizuku', null);
      }
      final ready = await privilegeReady();
      if (!ready) {
        throw PermissionException('没有访问权限，可在设置中开启 Root 或 Shizuku', null);
      }
      lastUsedPrivilege = true;
      return await privileged();
    }
  }

  @override
  Future<List<FileItem>> list(String path, {bool showHidden = true}) {
    return _guard(
      () => _local.list(path, showHidden: showHidden),
      () => _root.list(path, showHidden: showHidden),
    );
  }

  @override
  Future<VfsStat> stat(String path) {
    return _guard(() => _local.stat(path), () => _root.stat(path));
  }

  @override
  Future<bool> exists(String path) {
    return _guard(() => _local.exists(path), () => _root.exists(path));
  }

  @override
  @override
  Future<void> symlink(String target, String linkPath) {
    return _guard(
      () => _local.symlink(target, linkPath),
      () => _root.symlink(target, linkPath),
    );
  }

  @override
  Future<Uint8List> readBytes(String path) {
    return _guard(() => _local.readBytes(path), () => _root.readBytes(path));
  }

  @override
  Future<Uint8List> readHead(String path, {int limit = 8192}) {
    return _guard(
      () => _local.readHead(path, limit: limit),
      () => _root.readHead(path, limit: limit),
    );
  }

  @override
  Stream<List<int>> openRead(String path, {int? start, int? end}) {
    // 流式读取无法用 try/catch 包裹，先探测可读性再决定通道
    return _openReadSmart(path, start: start, end: end);
  }

  Stream<List<int>> _openReadSmart(String path, {int? start, int? end}) async* {
    var useRoot = false;
    try {
      await _local.stat(path);
      lastUsedPrivilege = false;
    } catch (e) {
      if (isPermissionError(e) && autoFallback && await privilegeReady()) {
        useRoot = true;
        lastUsedPrivilege = true;
      } else {
        rethrow;
      }
    }
    final src = useRoot
        ? _root.openRead(path, start: start, end: end)
        : _local.openRead(path, start: start, end: end);
    yield* src;
  }

  @override
  Future<void> writeBytes(String path, List<int> data) {
    return _guard(
      () => _local.writeBytes(path, data),
      () => _root.writeBytes(path, data),
    );
  }

  @override
  Future<void> mkdir(String path) {
    return _guard(() => _local.mkdir(path), () => _root.mkdir(path));
  }

  @override
  Future<void> delete(String path, {bool recursive = true}) {
    return _guard(
      () => _local.delete(path, recursive: recursive),
      () => _root.delete(path, recursive: recursive),
    );
  }

  @override
  Future<void> rename(String path, String newPath) {
    return _guard(
      () => _local.rename(path, newPath),
      () => _root.rename(path, newPath),
    );
  }

  @override
  Future<void> copy(String src, String dst) {
    return _guard(() => _local.copy(src, dst), () => _root.copy(src, dst));
  }

  @override
  Future<int> length(String path) {
    return _guard(() => _local.length(path), () => _root.length(path));
  }

  @override
  String normalize(String path) => _local.normalize(path);

  @override
  String join(String parent, String child) => _local.join(parent, child);

  @override
  String parent(String path) => _local.parent(path);

  @override
  String basename(String path) => _local.basename(path);
}
