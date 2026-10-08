// 压缩包浏览的测试。
//
// 注意：widget test 里 compute() 会与 FakeAsync 冲突而挂起，
// 所以涉及后台 isolate 的调用都用 tester.runAsync 包起来。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/services/archive/archive_service.dart';
import 'package:jy_file_manager/ui/pages/archive_page.dart';
import 'package:jy_file_manager/ui/widgets/app_list_tile.dart';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Localizations(
        locale: const Locale('en', 'US'),
        delegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: MiuixThemeController(
          child: SizedBox(width: 400, height: 700, child: child),
        ),
      ),
    );

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('jy_zip');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('ArchiveService 能读出 zip 内容', () async {
    final zipPath = '${tmp.path}/a.zip';
    File('test/fixtures/test.zip').copySync(zipPath);

    final archive = await ArchiveService.readArchive(zipPath);
    expect(archive, isNotNull);
    expect(archive!.files.length, 4);
    final names = archive.files.map((f) => f.name).toList();
    expect(names, contains('readme.txt'));
  });

  testWidgets('ArchivePage 能渲染出条目列表（列表项不依赖 Material 祖先）',
      (tester) async {
    final zipPath = '${tmp.path}/a.zip';
    File('test/fixtures/test.zip').copySync(zipPath);

    await tester.pumpWidget(
      _host(ArchivePage(path: zipPath, name: 'a.zip')),
    );

    // compute 在 FakeAsync 下不完成，用 runAsync 让它真正执行
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 顶层条目应显示出来
    expect(find.text('readme.txt'), findsOneWidget,
        reason: '根目录下的文件应显示');
    expect(find.text('src'), findsOneWidget, reason: '根目录下的目录应显示');
    expect(find.text('assets'), findsOneWidget);
  });

  testWidgets('AppListTile 在无 Material 祖先时也能渲染', (tester) async {
    // 模拟 MiuixScaffold 的环境：只有 MiuixSurface，没有 Material
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MiuixThemeController(
          child: MiuixSurface(
            color: const Color(0xFFFFFFFF),
            child: AppListTile(
              title: '测试项',
              subtitle: '副标题',
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('测试项'), findsOneWidget);
    expect(find.text('副标题'), findsOneWidget);
  });
}
