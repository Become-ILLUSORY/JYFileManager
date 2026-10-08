// 面板挂载：让一个面板临时浏览「非本地」的内容。
//
// 为什么要这样：远程目录与压缩包内部如果用全屏页面打开，
// 就没法跟本地目录之间直接复制（用户得来回切页面）。
// 成熟文件管理器的做法是把它们「挂载」到某一侧面板里 ——
// 左边看压缩包、右边看本地，直接拖过去就行。
//
// 实现上用一个前缀把挂载点编进路径里，例如：
//   /__mount__/zip:1712xxxx  →  压缩包根
//   /__mount__/zip:1712xxxx/src/main.dart
// 这样面板、导航、面包屑都不用改，只要在读写时把前缀还原成实际来源。
import 'package:flutter/foundation.dart';

/// 挂载类型
enum MountKind { archive, remote }

/// 一个挂载点
class Mount {
  Mount({
    required this.id,
    required this.kind,
    required this.label,
    required this.sourcePath,
  });

  /// 唯一 id（挂载后用作路径前缀的一部分）
  final String id;
  final MountKind kind;

  /// 显示名（如 `xxx.zip` 或 `webdav@服务器`）
  final String label;

  /// 来源：压缩包文件路径，或远程位置标识
  final String sourcePath;

  /// 挂载点虚拟根路径
  String get root => '$mountPrefix${kind.name}:$id';
}

/// 所有挂载路径的统一前缀
const String mountPrefix = '/__mount__/';

/// 全局挂载表
class MountRegistry extends ChangeNotifier {
  MountRegistry._();
  static final MountRegistry instance = MountRegistry._();

  final List<Mount> _mounts = [];
  List<Mount> get mounts => List.unmodifiable(_mounts);

  /// 注册一个挂载点，返回它的虚拟根路径
  String add({
    required MountKind kind,
    required String label,
    required String sourcePath,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final m = Mount(
      id: id,
      kind: kind,
      label: label,
      sourcePath: sourcePath,
    );
    _mounts.add(m);
    notifyListeners();
    return m.root;
  }

  /// 按虚拟根路径找挂载点
  Mount? byRoot(String root) {
    for (final m in _mounts) {
      if (m.root == root) return m;
    }
    return null;
  }

  /// 找出路径所属的挂载点
  Mount? ownerOf(String path) {
    for (final m in _mounts) {
      if (path == m.root || path.startsWith('${m.root}/')) return m;
    }
    return null;
  }

  /// 卸载
  void remove(String root) {
    _mounts.removeWhere((m) => m.root == root);
    notifyListeners();
  }

  /// 清理所有挂载（退出远程页时调用）
  void clear() {
    _mounts.clear();
    notifyListeners();
  }

  /// 判断某路径是否为挂载路径
  static bool isMountPath(String path) => path.startsWith(mountPrefix);

  /// 把挂载路径里的「内部路径」提取出来
  ///
  /// `/__mount__/zip:123/src/a.dart` → `/src/a.dart`
  static String? innerPath(String path) {
    if (!isMountPath(path)) return null;
    final rest = path.substring(mountPrefix.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? '/' : rest.substring(slash);
  }
}
