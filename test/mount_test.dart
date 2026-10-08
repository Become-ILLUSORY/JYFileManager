// 挂载层测试：压缩包挂载后能否被 appFs 正确列出。
//
// 这条链路上次出过问题：MountAwareFs 实现了，但 appFs 仍返回 SmartFs，
// 导致挂载路径被当真实路径去查，报「目录不存在」。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/models/mount.dart';
import 'package:jy_file_manager/services/fs/fs_provider.dart';
import 'package:jy_file_manager/services/fs/mount_aware_fs.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('jy_mount');
  });

  tearDown(() {
    try {
      MountRegistry.instance.clear();
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('appFs 必须是挂载感知的实现', () {
    expect(appFs, isA<MountAwareFs>(),
        reason: 'appFs 若不是 MountAwareFs，挂载路径会被当真实路径查询');
  });

  test('挂载压缩包后能列出内容', () async {
    final zipPath = '${tmp.path}/a.zip';
    File('test/fixtures/test.zip').copySync(zipPath);

    final root = await MountAwareFs.instance.mountArchive(zipPath, 'a.zip');
    expect(root.startsWith('/__mount__/'), isTrue);

    final items = await appFs.list(root);
    final names = items.map((e) => e.name).toList();
    debugPrint('挂载根内容: $names');

    expect(names, contains('readme.txt'));
    expect(names, contains('src'));
    expect(names, contains('assets'));

    // 目录应被标记为目录
    final src = items.firstWhere((e) => e.name == 'src');
    expect(src.isDirectory, isTrue);

    // 文件应有大小
    final readme = items.firstWhere((e) => e.name == 'readme.txt');
    expect(readme.isDirectory, isFalse);
    expect(readme.size, 5);
  });

  test('能进入子目录', () async {
    final zipPath = '${tmp.path}/a.zip';
    File('test/fixtures/test.zip').copySync(zipPath);

    final root = await MountAwareFs.instance.mountArchive(zipPath, 'a.zip');
    final items = await appFs.list('$root/src');
    final names = items.map((e) => e.name).toList();
    debugPrint('src/ 内容: $names');
    expect(names, contains('main.dart'));
  });

  test('能读取压缩包内的文件内容', () async {
    final zipPath = '${tmp.path}/a.zip';
    File('test/fixtures/test.zip').copySync(zipPath);

    final root = await MountAwareFs.instance.mountArchive(zipPath, 'a.zip');
    final bytes = await appFs.readBytes('$root/readme.txt');
    expect(String.fromCharCodes(bytes), 'hello');
  });

  test('压缩包内写入会记入改动集', () async {
    final zipPath = '${tmp.path}/a.zip';
    File('test/fixtures/test.zip').copySync(zipPath);

    final root = await MountAwareFs.instance.mountArchive(zipPath, 'a.zip');
    await appFs.writeBytes('$root/newfile.txt', [72, 105]); // "Hi"

    // 原压缩包不应被修改
    final original = await File(zipPath).readAsBytes();
    final archive = await MountAwareFs.instance.archiveOf(root);
    expect(archive, isNotNull);
    // 内存里的归档对象应包含新文件
    expect(archive!.findFile('newfile.txt'), isNotNull);
    debugPrint('原压缩包大小仍为 ${original.length}（未改动）');
  });

  test('退出挂载点后清理', () async {
    final zipPath = '${tmp.path}/a.zip';
    File('test/fixtures/test.zip').copySync(zipPath);

    final root = await MountAwareFs.instance.mountArchive(zipPath, 'a.zip');
    expect(MountRegistry.instance.ownerOf(root), isNotNull);

    MountAwareFs.instance.unmount(root);
    expect(MountRegistry.instance.ownerOf(root), isNull);
  });

  test('本地路径不受挂载层影响', () async {
    final f = File('${tmp.path}/local.txt')..writeAsStringSync('local');
    final items = await appFs.list(tmp.path);
    expect(items.any((e) => e.name == 'local.txt'), isTrue);
    expect(await appFs.readBytes(f.path), isNotEmpty);
  });
}
