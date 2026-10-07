// 批量重命名表达式的测试。
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/utils/batch_rename.dart';
import 'package:jy_file_manager/core/utils/text_file_kinds.dart';

void main() {
  group('日期格式', () {
    final d = DateTime(2026, 3, 7, 15, 4, 9, 123); // 周六

    test('常用模式', () {
      expect(BatchRename.formatDate(d, 'yyyy-MM-dd'), '2026-03-07');
      expect(BatchRename.formatDate(d, 'yy/MM/dd'), '26/03/07');
      expect(BatchRename.formatDate(d, 'HH:mm:ss'), '15:04:09');
      expect(BatchRename.formatDate(d, 'hh:mm'), '03:04');
      expect(BatchRename.formatDate(d, 'SSS'), '123');
      expect(BatchRename.formatDate(d, 'Q'), '1');
    });

    test('月份与星期名称', () {
      expect(BatchRename.formatDate(d, 'MMMM'), 'March');
      expect(BatchRename.formatDate(d, 'MMM'), 'Mar');
      expect(BatchRename.formatDate(d, 'EEEE'), 'Saturday');
      expect(BatchRename.formatDate(d, 'EEE'), 'Sat');
    });

    test('组合模式（长 token 优先，不被短 token 抢）', () {
      expect(
        BatchRename.formatDate(d, 'yyyyMMdd_HHmmss'),
        '20260307_150409',
      );
      expect(BatchRename.formatDate(d, 'yy-M-d'), '26-3-7');
    });
  });

  group('表达式占位符', () {
    List<RenamePlan> plan(
      List<String> names, {
      required String tpl,
      int start = 1,
      int step = 1,
    }) {
      var i = 0;
      return BatchRename.plan(
        files: [
          for (final n in names)
            (
              path: '/dir/$n',
              name: n,
              modified: DateTime(2026, 1, 1 + i++),
              size: (i) * 1024,
            ),
        ],
        template: tpl,
        startNumber: start,
        step: step,
      );
    }

    test('{P} 原名与 {E} 扩展名', () {
      final p = plan(['photo.jpg'], tpl: '{P}_backup.{E}');
      expect(p.first.newName, 'photo_backup.jpg');
    });

    test('{N} 序号与 {zN} 补零', () {
      final p = plan(['a.txt', 'b.txt', 'c.txt'], tpl: 'file_{z3}');
      expect(p[0].newName, 'file_001.txt');
      expect(p[1].newName, 'file_002.txt');
      expect(p[2].newName, 'file_003.txt');
    });

    test('起始序号与步长', () {
      final p = plan(['a.txt', 'b.txt'], tpl: 'x{N}', start: 10, step: 5);
      expect(p[0].newName, 'x10.txt');
      expect(p[1].newName, 'x15.txt');
    });

    test('模板未含 {E} 时自动保留原扩展名', () {
      final p = plan(['report.pdf'], tpl: 'final');
      expect(p.first.newName, 'final.pdf');
    });

    test('{T:fmt} 自定义时间格式', () {
      final p = plan(['a.txt'], tpl: 'log_{T:yyyy-MM-dd}');
      expect(p.first.newName, 'log_2026-01-01.txt');
    });

    test('{D} 默认日期格式', () {
      final p = plan(['a.txt'], tpl: '{D}_data');
      expect(p.first.newName, '20260101_data.txt');
    });

    test('{S} 文件大小', () {
      final p = plan(['a.txt'], tpl: 'size_{S}');
      expect(p.first.newName, contains('KB'));
    });

    test('排序序号 {AN} {AD} {AS}', () {
      // 三个文件：名字倒序、日期正序、大小递增
      final plans = BatchRename.plan(
        files: [
          (path: '/d/c.txt', name: 'c.txt', modified: DateTime(2026, 1, 1), size: 100),
          (path: '/d/a.txt', name: 'a.txt', modified: DateTime(2026, 1, 2), size: 200),
          (path: '/d/b.txt', name: 'b.txt', modified: DateTime(2026, 1, 3), size: 300),
        ],
        template: 'n{AN}d{AD}s{AS}',
      );
      // c.txt：名字序 3、日期序 1、大小序 1
      expect(plans[0].newName, 'n3d1s1.txt');
      // a.txt：名字序 1、日期序 2、大小序 2
      expect(plans[1].newName, 'n1d2s2.txt');
      // b.txt：名字序 2、日期序 3、大小序 3
      expect(plans[2].newName, 'n2d3s3.txt');
    });
  });

  group('校验', () {
    test('重名会被检出', () {
      final plans = BatchRename.plan(
        files: [
          (path: '/d/a.txt', name: 'a.txt', modified: DateTime(2026), size: 1),
          (path: '/d/b.txt', name: 'b.txt', modified: DateTime(2026), size: 2),
        ],
        template: 'same', // 两个都叫 same
      );
      final errors = BatchRename.validate(plans);
      expect(errors, isNotEmpty);
      expect(errors.first, contains('重名'));
    });

    test('正常模板无错误', () {
      final plans = BatchRename.plan(
        files: [
          (path: '/d/a.txt', name: 'a.txt', modified: DateTime(2026), size: 1),
          (path: '/d/b.txt', name: 'b.txt', modified: DateTime(2026), size: 2),
        ],
        template: 'f{z2}',
      );
      expect(BatchRename.validate(plans), isEmpty);
    });

    test('未改名的项 changed 为 false', () {
      final plans = BatchRename.plan(
        files: [
          (path: '/d/a.txt', name: 'a.txt', modified: DateTime(2026), size: 1),
        ],
        template: '{P}.{E}', // 原名 + 原扩展名 → 不变
      );
      expect(plans.first.changed, isFalse);
    });
  });

  group('压缩包格式识别', () {
    test('常见压缩包应被识别', () {
      for (final n in [
        'a.zip', 'b.tar', 'c.tar.gz', 'd.tar.bz2', 'e.tar.xz',
        'f.tgz', 'g.jar', 'h.apk', 'i.7z', 'j.rar', 'k.gz',
      ]) {
        expect(ArchiveKinds.isArchive(n), isTrue, reason: '$n 应识别为压缩包');
      }
    });

    test('普通文件不应被识别为压缩包', () {
      for (final n in ['a.txt', 'b.png', 'c.mp4', 'd.dart', 'e.pdf']) {
        expect(ArchiveKinds.isArchive(n), isFalse, reason: '$n 不是压缩包');
      }
    });
  });
}
