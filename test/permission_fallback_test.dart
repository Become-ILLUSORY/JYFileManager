// 权限回退逻辑的测试。
//
// 关键背景：Android 的存储沙箱在「无权限」时返回的是 ENOENT（"不存在"）
// 而不是 EACCES，所以不能只靠异常类型判断要不要回退到 root。
// 这组测试锁定这个行为，防止回归。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/services/fs/smart_fs.dart';
import 'package:jy_file_manager/services/fs/vfs.dart';

void main() {
  group('错误分类', () {
    test('明确的权限错误应被识别', () {
      expect(
        SmartFs.isPermissionError(
          const FileSystemException('Permission denied', '/x'),
        ),
        isTrue,
      );
      expect(SmartFs.isPermissionError('EACCES'), isTrue);
      expect(
        SmartFs.isPermissionError(PermissionException('无权限', '/x')),
        isTrue,
      );
    });

    test('ENOENT 不算「权限错误」（Android 会用它伪装无权限）', () {
      // 这是关键：Android 沙箱把无权限报成「不存在」，
      // 所以 isPermissionError 对它返回 false —— 因此回退策略
      // 不能只依赖这个判断。
      expect(
        SmartFs.isPermissionError(
          const FileSystemException('No such file or directory', '/x'),
        ),
        isFalse,
      );
    });
  });

  group('VfsStat', () {
    test('notFound 的状态', () {
      const s = VfsStat.notFound();
      expect(s.exists, isFalse);
      expect(s.isDirectory, isFalse);
    });

    test('目录状态', () {
      final s = VfsStat(
        exists: true,
        isDirectory: true,
        size: 0,
        modified: DateTime(2026),
      );
      expect(s.exists, isTrue);
      expect(s.isDirectory, isTrue);
    });
  });
}
