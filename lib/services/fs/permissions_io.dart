// 存储权限申请（原生平台：Android 11+ 需 MANAGE_EXTERNAL_STORAGE 才能访问 /sdcard）
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 权限状态
enum StorageAccess {
  /// 完全可用（可读写外部存储）
  granted,

  /// 仅部分可用（Android 13+ 的媒体权限，非 /sdcard 全盘）
  limited,

  /// 被拒绝，需要用户去设置页授权
  denied,
}

class StoragePermissions {
  StoragePermissions._();

  /// 检查当前是否有全盘文件访问权限
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  /// 申请全盘文件访问权限。
  ///
  /// Android 11+ 的 MANAGE_EXTERNAL_STORAGE 会跳到系统「所有文件访问权限」页面，
  /// 用户授权后 App 会被系统重启，所以这里只需发起请求。
  /// 返回是否已授权（跳转类请求通常返回 false，需用户回来后再查）。
  static Future<StorageAccess> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return StorageAccess.granted;

    if (await Permission.manageExternalStorage.isGranted) {
      return StorageAccess.granted;
    }

    final result = await Permission.manageExternalStorage.request();
    if (result.isGranted) return StorageAccess.granted;
    if (result.isPermanentlyDenied || result.isRestricted) {
      return StorageAccess.denied;
    }

    // 退回申请常规存储/媒体权限，至少能读相册等公共目录
    final legacy = await [
      Permission.storage,
      Permission.photos,
      Permission.videos,
      Permission.audio,
      Permission.notification,
    ].request();

    final anyGranted = legacy.values.any((s) => s.isGranted);
    return anyGranted ? StorageAccess.limited : StorageAccess.denied;
  }

  /// 打开系统应用详情页（让用户手动开启权限）
  static Future<bool> openSettings() => openAppSettings();
}
