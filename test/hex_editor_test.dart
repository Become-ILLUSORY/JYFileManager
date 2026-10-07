// Hex 编辑器的核心逻辑测试（不依赖 UI）。
//
// 覆盖：行数计算、按行取字节、偏移格式化、ASCII 列渲染规则。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 与 hex_editor_page 保持一致的常量
const int bytesPerLine = 16;

/// 计算总行数
int totalRows(int fileSize) => (fileSize / bytesPerLine).ceil();

/// 取某一行的字节（模拟编辑器逻辑）
Uint8List rowBytes(Uint8List data, int row) {
  final offset = row * bytesPerLine;
  if (offset >= data.length) return Uint8List(0);
  final end = (offset + bytesPerLine).clamp(0, data.length);
  return Uint8List.sublistView(data, offset, end);
}

/// 格式化偏移（8 位十六进制）
String formatOffset(int offset) => offset.toRadixString(16).padLeft(8, '0');

/// 渲染一行的十六进制列（含中间分组）
String hexColumn(Uint8List bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytesPerLine; i++) {
    if (i < bytes.length) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    } else {
      sb.write('  ');
    }
    if (i == 7) sb.write('  ');
    sb.write(' ');
  }
  return sb.toString();
}

/// 渲染 ASCII 列：可打印字符原样，其余用点
String asciiColumn(Uint8List bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytesPerLine; i++) {
    if (i < bytes.length) {
      final b = bytes[i];
      sb.write(b >= 0x20 && b < 0x7F ? String.fromCharCode(b) : '.');
    } else {
      sb.write(' ');
    }
  }
  return sb.toString();
}

void main() {
  group('行数计算', () {
    test('整除与非整除', () {
      expect(totalRows(0), 0);
      expect(totalRows(1), 1);
      expect(totalRows(16), 1);
      expect(totalRows(17), 2);
      expect(totalRows(1024), 64);
    });

    test('大文件', () {
      expect(totalRows(1024 * 1024), 65536);
    });
  });

  group('按行取字节', () {
    test('完整行', () {
      final data = Uint8List.fromList(List.generate(64, (i) => i));
      final r0 = rowBytes(data, 0);
      expect(r0.length, 16);
      expect(r0[0], 0);
      expect(r0[15], 15);

      final r2 = rowBytes(data, 2);
      expect(r2[0], 32);
      expect(r2[15], 47);
    });

    test('最后一行不足 16 字节', () {
      final data = Uint8List.fromList(List.generate(20, (i) => i));
      expect(rowBytes(data, 0).length, 16);
      expect(rowBytes(data, 1).length, 4);
      expect(rowBytes(data, 2).length, 0); // 越界
    });
  });

  group('偏移格式', () {
    test('补零到 8 位', () {
      expect(formatOffset(0), '00000000');
      expect(formatOffset(15), '0000000f');
      expect(formatOffset(255), '000000ff');
      expect(formatOffset(4096), '00001000');
      expect(formatOffset(0xDEADBEEF), 'deadbeef');
    });
  });

  group('十六进制列', () {
    test('满行含中间分组', () {
      final bytes = Uint8List.fromList(List.generate(16, (i) => i));
      final hex = hexColumn(bytes);
      // 前 8 字节 + 分组双空格 + 后 8 字节
      // 分组处有两个空格，加上每字节后的单空格，实际是三个
      expect(hex.startsWith('00 01 02 03 04 05 06 07   08'), isTrue);
      // 每组「xx 」占 3 字符共 48，中间分组多 1 个空格，行尾再多 1 个 → 50
      expect(hex.length, 50);
    });

    test('不足一行时用空格补齐', () {
      final bytes = Uint8List.fromList([0xAB, 0xCD]);
      final hex = hexColumn(bytes);
      expect(hex.startsWith('ab cd'), isTrue);
      expect(hex.length, 50, reason: '补空格后应与满行等长，保证列对齐');
    });
  });

  group('ASCII 列', () {
    test('可打印字符原样显示', () {
      final bytes = Uint8List.fromList(
        [0x48, 0x65, 0x6C, 0x6C, 0x6F], // "Hello"
      );
      expect(asciiColumn(bytes).startsWith('Hello'), isTrue);
    });

    test('不可打印字符用点替代', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x1F, 0x7F, 0x80, 0xFF]);
      final ascii = asciiColumn(bytes);
      expect(ascii.startsWith('......'), isTrue);
    });

    test('边界：0x20 是空格（可打印），0x7F 是 DEL（不可打印）', () {
      expect(asciiColumn(Uint8List.fromList([0x20])).startsWith(' '), isTrue);
      expect(asciiColumn(Uint8List.fromList([0x7F])).startsWith('.'), isTrue);
      expect(asciiColumn(Uint8List.fromList([0x7E])).startsWith('~'), isTrue);
    });

    test('不足一行时补齐空格', () {
      final bytes = Uint8List.fromList([0x41]); // "A"
      final ascii = asciiColumn(bytes);
      expect(ascii.length, 16);
      expect(ascii[0], 'A');
      expect(ascii.substring(1).trim(), '');
    });
  });

  group('真实文件头识别（回归）', () {
    test('PNG 头应被正确渲染', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(hexColumn(png).startsWith('89 50 4e 47 0d 0a 1a 0a'), isTrue);
      // PNG 在 ASCII 列里显示为 .PNG....
      expect(asciiColumn(png).startsWith('.PNG....'), isTrue);
    });

    test('ZIP 头应被正确渲染', () {
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
      expect(hexColumn(zip).startsWith('50 4b 03 04'), isTrue);
      expect(asciiColumn(zip).startsWith('PK..'), isTrue);
    });
  });
}
