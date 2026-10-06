// Web 预览下的权限桩：浏览器无需存储权限，直接视为已授权
/// 权限状态（与原生实现保持一致）
enum StorageAccess { granted, limited, denied }

class StoragePermissions {
  StoragePermissions._();

  static Future<bool> hasAllFilesAccess() async => true;

  static Future<StorageAccess> requestAllFilesAccess() async =>
      StorageAccess.granted;

  static Future<bool> openSettings() async => false;
}
