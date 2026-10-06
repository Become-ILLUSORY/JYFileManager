// 文本编码检测与转换工具
//
// 支持 UTF-8 / UTF-16 / GBK / GB18030 / Big5 等常见编码，
// 用于文本编辑器、代码查看器等场景。
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

/// 支持的文本编码
enum TextEncoding {
  utf8('UTF-8'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  gbk('GBK'),
  gb18030('GB18030'),
  big5('Big5'),
  latin1('ISO-8859-1');

  final String label;
  const TextEncoding(this.label);

  static TextEncoding fromLabel(String label) {
    return TextEncoding.values.firstWhere(
      (e) => e.label == label,
      orElse: () => TextEncoding.utf8,
    );
  }
}

/// 编码检测结果
class EncodingDetection {
  final TextEncoding encoding;
  final double confidence;
  const EncodingDetection(this.encoding, this.confidence);
}

/// 文本编码工具
class TextCodecUtil {
  TextCodecUtil._();

  /// 检测字节流的编码。
  ///
  /// 策略：
  /// 1. BOM 检测（最可靠）
  /// 2. 严格 UTF-8 解码尝试
  /// 3. GBK / Big5 启发式判断（中文字符占比）
  static EncodingDetection detect(Uint8List bytes, {int sampleSize = 65536}) {
    final sample =
        bytes.length > sampleSize ? bytes.sublist(0, sampleSize) : bytes;

    // 1. BOM
    if (sample.length >= 3 &&
        sample[0] == 0xEF &&
        sample[1] == 0xBB &&
        sample[2] == 0xBF) {
      return const EncodingDetection(TextEncoding.utf8, 1.0);
    }
    if (sample.length >= 2 && sample[0] == 0xFF && sample[1] == 0xFE) {
      return const EncodingDetection(TextEncoding.utf16le, 1.0);
    }
    if (sample.length >= 2 && sample[0] == 0xFE && sample[1] == 0xFF) {
      return const EncodingDetection(TextEncoding.utf16be, 1.0);
    }

    // 2. 严格 UTF-8
    try {
      const Utf8Decoder(allowMalformed: false).convert(sample);
      // 纯 ASCII 也可用 UTF-8
      return const EncodingDetection(TextEncoding.utf8, 0.95);
    } catch (_) {}

    // 3. 中文编码启发式
    final gbkScore = _scoreChineseEncoding(sample, gbk);
    final big5Score = _scoreChineseEncoding(sample, big5);
    if (gbkScore > big5Score && gbkScore > 0.3) {
      return EncodingDetection(TextEncoding.gbk, gbkScore);
    }
    if (big5Score > 0.3) {
      return EncodingDetection(TextEncoding.big5, big5Score);
    }

    return const EncodingDetection(TextEncoding.utf8, 0.5);
  }

  /// 计算用指定编码解码后"像中文文本"的程度
  static double _scoreChineseEncoding(Uint8List bytes, Encoding codec) {
    try {
      final text = codec.decode(bytes);
      if (text.isEmpty) return 0;
      var chinese = 0, printable = 0, replacement = 0;
      for (final rune in text.runes) {
        if (rune == 0xFFFD) {
          replacement++;
          continue;
        }
        if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
            (rune >= 0x3000 && rune <= 0x303F) ||
            (rune >= 0xFF00 && rune <= 0xFFEF)) {
          chinese++;
        }
        if (rune >= 0x20 && rune != 0x7F) printable++;
      }
      final total = text.runes.length;
      if (total == 0) return 0;
      // 替换字符多说明解码失败
      if (replacement / total > 0.1) return 0;
      return (chinese / total) * 0.7 + (printable / total) * 0.3;
    } catch (_) {
      return 0;
    }
  }

  /// 按指定编码解码
  static String decode(Uint8List bytes, TextEncoding encoding) {
    switch (encoding) {
      case TextEncoding.utf8:
        // 跳过 BOM
        if (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF) {
          return const Utf8Decoder(allowMalformed: true)
              .convert(bytes.sublist(3));
        }
        return const Utf8Decoder(allowMalformed: true).convert(bytes);
      case TextEncoding.utf16le:
        return _decodeUtf16(bytes, littleEndian: true);
      case TextEncoding.utf16be:
        return _decodeUtf16(bytes, littleEndian: false);
      case TextEncoding.gbk:
      case TextEncoding.gb18030:
        return gbk.decode(bytes);
      case TextEncoding.big5:
        return big5.decode(bytes);
      case TextEncoding.latin1:
        return latin1.decode(bytes);
    }
  }

  /// 按指定编码编码
  static Uint8List encode(String text, TextEncoding encoding) {
    switch (encoding) {
      case TextEncoding.utf8:
        return Uint8List.fromList(utf8.encode(text));
      case TextEncoding.utf16le:
        return _encodeUtf16(text, littleEndian: true);
      case TextEncoding.utf16be:
        return _encodeUtf16(text, littleEndian: false);
      case TextEncoding.gbk:
      case TextEncoding.gb18030:
        return Uint8List.fromList(gbk.encode(text));
      case TextEncoding.big5:
        return Uint8List.fromList(big5.encode(text));
      case TextEncoding.latin1:
        return Uint8List.fromList(latin1.encode(text));
    }
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    var offset = 0;
    if (bytes.length >= 2) {
      final b0 = bytes[0], b1 = bytes[1];
      if ((b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF)) {
        offset = 2;
      }
    }
    final codeUnits = <int>[];
    for (var i = offset; i + 1 < bytes.length; i += 2) {
      codeUnits.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }

  static Uint8List _encodeUtf16(String text, {required bool littleEndian}) {
    final out = BytesBuilder();
    // 写入 BOM
    if (littleEndian) {
      out.add([0xFF, 0xFE]);
    } else {
      out.add([0xFE, 0xFF]);
    }
    for (final unit in text.codeUnits) {
      if (littleEndian) {
        out.add([unit & 0xFF, (unit >> 8) & 0xFF]);
      } else {
        out.add([(unit >> 8) & 0xFF, unit & 0xFF]);
      }
    }
    return out.toBytes();
  }

  /// 判断字节流是否像二进制文件（用于编辑器打开前检查）
  static bool looksBinary(Uint8List bytes, {int sampleSize = 8192}) {
    final n = bytes.length < sampleSize ? bytes.length : sampleSize;
    if (n == 0) return false;
    var suspicious = 0;
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      // 允许 \t \n \r \f \b 等控制字符
      if (b == 0) return true;
      if (b < 0x09 || (b > 0x0D && b < 0x20)) suspicious++;
    }
    return suspicious / n > 0.3;
  }

  /// 粗略行数统计（用于大文件预览优化）
  static int countLines(Uint8List bytes, {int sampleSize = 1024 * 1024}) {
    final n = bytes.length < sampleSize ? bytes.length : sampleSize;
    var lines = 1;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0x0A) lines++;
    }
    return lines;
  }
}
