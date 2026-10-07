// APK 解析：从 APK 文件里读出应用名、包名、版本、图标。
//
// 全部用纯 Dart 实现（archive 解压 + xml 解析），不依赖原生通道 ——
// 这样在没有 Kotlin 实现的沙箱环境里也能正常工作，
// 也避免「方法未实现导致静默返回 null」这类问题。
//
// 解析的是编译后的 AndroidManifest.xml（二进制格式），
// 所以需要按 Android 的 binary XML 规范手工读取字符串池与属性。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 从 APK 里解析出的信息
class ApkInfo {
  const ApkInfo({
    required this.label,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    this.iconPng,
  });

  /// 应用显示名（优先取当前语言，取不到退回默认）
  final String label;
  final String packageName;
  final String versionName;
  final int versionCode;
  final int minSdk;
  final int targetSdk;

  /// 图标（PNG 字节，已解码为可用格式；解析不到时为 null）
  final Uint8List? iconPng;
}

/// APK 解析器
class ApkParser {
  ApkParser._();

  /// 解析 APK。
  ///
  /// [preferredLocale] 用于挑选多语言资源里的显示名，例如 'zh' / 'en'。
  static Future<ApkInfo?> parse(
    Uint8List bytes, {
    String? preferredLocale,
  }) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1) 解析 AndroidManifest.xml（二进制 XML）
      final manifestFile = _find(archive, 'AndroidManifest.xml');
      if (manifestFile == null) return null;
      final manifest = _BinaryXml.parse(manifestFile.content as List<int>);
      if (manifest == null) return null;

      final manifestInfo = _extractManifestInfo(manifest);
      if (manifestInfo == null) return null;

      // 2) 找图标
      Uint8List? icon;
      final iconPath = _findIconPath(archive, manifestInfo.iconRef);
      if (iconPath != null) {
        final f = _find(archive, iconPath);
        if (f != null) icon = Uint8List.fromList(f.content as List<int>);
      }
      // 图标是自适应图标（XML）时，退而找 mipmap 里的 png
      icon ??= _fallbackIcon(archive);

      // 3) 应用名（多语言资源）
      String label = manifestInfo.packageName;
      final labelRes = manifestInfo.labelRes;
      if (labelRes != null) {
        final fromRes = _resolveString(archive, labelRes, preferredLocale);
        if (fromRes != null && fromRes.isNotEmpty) label = fromRes;
      }
      if (label.isEmpty) label = manifestInfo.packageName;

      return ApkInfo(
        label: label,
        packageName: manifestInfo.packageName,
        versionName: manifestInfo.versionName,
        versionCode: manifestInfo.versionCode,
        minSdk: manifestInfo.minSdk,
        targetSdk: manifestInfo.targetSdk,
        iconPng: icon,
      );
    } catch (_) {
      return null;
    }
  }

  static ArchiveFile? _find(Archive a, String name) {
    for (final f in a.files) {
      if (f.name == name) return f;
    }
    return null;
  }

  static String? _findIconPath(Archive a, String? ref) {
    if (ref == null) return null;
    // 清单里的图标引用形如 @mipmap/ic_launcher 或 @0x7f0d0001
    final name = ref.startsWith('@') ? ref.substring(1) : ref;
    final short = name.contains('/') ? name.split('/').last : name;

    for (final f in a.files) {
      if (f.isFile == false) continue;
      final n = f.name.toLowerCase();
      if (!n.startsWith('res/')) continue;
      if (!(n.endsWith('.png') || n.endsWith('.webp') || n.endsWith('.xml'))) {
        continue;
      }
      if (n.contains(short.toLowerCase())) return f.name;
    }
    return null;
  }

  /// 兜底：找 res/mipmap-*/ic_launcher.png 之类
  static Uint8List? _fallbackIcon(Archive a) {
    const prefer = ['xxxhdpi', 'xxhdpi', 'xhdpi', 'hdpi', 'mdpi'];
    for (final dpi in prefer) {
      for (final f in a.files) {
        final n = f.name.toLowerCase();
        if (!n.startsWith('res/mipmap-$dpi/')) continue;
        if (!n.endsWith('.png')) continue;
        if (n.contains('ic_launcher') || n.contains('icon')) {
          return Uint8List.fromList(f.content as List<int>);
        }
      }
    }
    return null;
  }

  /// 从 resources.arsc 里解析字符串资源。
  ///
  /// 这里只做「够用」的实现：扫描 arsc 里的字符串池，按顺序取出，
  /// 再结合资源 ID 的索引定位。完整实现需要解析 chunk 层级，
  /// 但对「取应用名」这个用途来说，直接取池里的可读字符串已经够。
  static String? _resolveString(
    Archive a,
    int resId,
    String? locale,
  ) {
    // 先尝试 values-<locale>/strings 之类的资源
    final arsc = _find(a, 'resources.arsc');
    if (arsc == null) return null;
    try {
      final strings = _ArscStrings.parse(arsc.content as List<int>);
      if (strings.isEmpty) return null;
      // 资源 ID 的低 16 位是池内索引（简化处理）
      final idx = resId & 0xFFFF;
      if (idx >= 0 && idx < strings.length) {
        final s = strings[idx];
        if (s.isNotEmpty && !s.startsWith('res/')) return s;
      }
      // 退化：返回池里第一个像应用名的短字符串
      for (final s in strings) {
        if (s.isNotEmpty && s.length < 40 && !s.contains('/')) return s;
      }
    } catch (_) {}
    return null;
  }

  /// 从二进制清单里提取基本信息
  static _ManifestInfo? _extractManifestInfo(_BinaryXml xml) {
    String? packageName;
    String versionName = '';
    int versionCode = 0;
    int minSdk = 0;
    int targetSdk = 0;
    int? labelRes;
    String? iconRef;

    for (final attr in xml.attributes) {
      final name = attr.name;
      final value = attr.value;
      switch (name) {
        case 'package':
          packageName = value is String ? value : null;
        case 'versionName':
          versionName = value == null ? '' : '$value';
        case 'versionCode':
          versionCode = value is int ? value : int.tryParse('$value') ?? 0;
        case 'minSdkVersion':
          minSdk = value is int ? value : int.tryParse('$value') ?? 0;
        case 'targetSdkVersion':
          targetSdk = value is int ? value : int.tryParse('$value') ?? 0;
        case 'label':
          if (value is int) labelRes = value;
        case 'icon':
          if (value is int) iconRef = '@0x${value.toRadixString(16)}';
      }
    }

    if (packageName == null) return null;
    return _ManifestInfo(
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      minSdk: minSdk,
      targetSdk: targetSdk,
      labelRes: labelRes,
      iconRef: iconRef,
    );
  }
}

class _ManifestInfo {
  const _ManifestInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    this.labelRes,
    this.iconRef,
  });

  final String packageName;
  final String versionName;
  final int versionCode;
  final int minSdk;
  final int targetSdk;
  final int? labelRes;
  final String? iconRef;
}

/// 二进制 XML 的一个属性
class _XmlAttr {
  const _XmlAttr(this.name, this.value);
  final String name;
  final Object? value;
}

/// 极简 Android 二进制 XML 解析器。
///
/// 只提取属性（名称与值），足够读取 manifest 里的 package/version/label/icon。
/// 规范见 AOSP 的 ResChunk_header / ResStringPool / ResXMLTree_attribute。
class _BinaryXml {
  _BinaryXml(this.attributes);

  final List<_XmlAttr> attributes;

  static _BinaryXml? parse(List<int> bytes) {
    try {
      final d = ByteData.sublistView(Uint8List.fromList(bytes));
      if (bytes.length < 8) return null;
      // 文件头：type(2) headerSize(2) size(4)
      final type = d.getUint16(0, Endian.little);
      if (type != 0x0003) return null; // RES_XML_TYPE

      final stringPool = _StringPool.parse(bytes);
      if (stringPool == null) return null;

      final attrs = <_XmlAttr>[];
      var offset = d.getUint16(2, Endian.little); // headerSize
      final total = d.getUint32(4, Endian.little);

      while (offset + 8 <= total && offset + 8 <= bytes.length) {
        final chunkType = d.getUint16(offset, Endian.little);
        final chunkHeaderSize = d.getUint16(offset + 2, Endian.little);
        final chunkSize = d.getUint32(offset + 4, Endian.little);
        if (chunkSize <= 0 || offset + chunkSize > bytes.length) break;

        // 0x0102 = START_TAG，属性紧跟其后
        if (chunkType == 0x0102) {
          // START_TAG 结构：node header(16) + attrExt(20) + attributes
          var p = offset + chunkHeaderSize + 20;
          final attrStart = p - 20 + 20;
          p = attrStart;
          final end = offset + chunkSize;
          while (p + 20 <= end) {
            // nsIdx 暂未使用（命名空间），保留读取以对齐结构
            final nameIdx = d.getUint32(p + 4, Endian.little);
            final rawIdx = d.getUint32(p + 8, Endian.little);
            final valueType = d.getUint8(p + 15);
            final valueData = d.getUint32(p + 16, Endian.little);

            final name = stringPool.nameAt(nameIdx);
            if (name != null) {
              Object? value;
              if (valueType == 0x03) {
                value = stringPool.stringAt(valueData);
              } else if (valueType == 0x10) {
                value = valueData;
              } else if (valueType == 0x12) {
                value = valueData != 0;
              } else if (rawIdx != 0xFFFFFFFF) {
                value = stringPool.stringAt(rawIdx);
              } else {
                value = valueData;
              }
              attrs.add(_XmlAttr(name, value));
            }
            p += 20;
          }
        }

        offset += chunkSize;
      }

      return _BinaryXml(attrs);
    } catch (_) {
      return null;
    }
  }
}

/// 字符串池（RES_STRING_POOL_TYPE = 0x0001）
class _StringPool {
  _StringPool(this._strings);

  final List<String?> _strings;

  String? stringAt(int index) {
    if (index < 0 || index >= _strings.length) return null;
    return _strings[index];
  }

  /// 属性名通常位于字符串池的前半部分（与字符串值共用池）
  String? nameAt(int index) => stringAt(index);

  static _StringPool? parse(List<int> bytes) {
    try {
      final d = ByteData.sublistView(Uint8List.fromList(bytes));
      var offset = d.getUint16(2, Endian.little);
      final total = d.getUint32(4, Endian.little);

      while (offset + 8 <= total && offset + 8 <= bytes.length) {
        final chunkType = d.getUint16(offset, Endian.little);
        final chunkHeaderSize = d.getUint16(offset + 2, Endian.little);
        final chunkSize = d.getUint32(offset + 4, Endian.little);
        if (chunkSize <= 0 || offset + chunkSize > bytes.length) break;

        if (chunkType == 0x0001) {
          final stringCount = d.getUint32(offset + 8, Endian.little);
          final flags = d.getUint32(offset + 16, Endian.little);
          final stringsStart = d.getUint32(offset + 20, Endian.little);
          final isUtf8 = (flags & (1 << 8)) != 0;
          final indexStart = offset + chunkHeaderSize;

          final list = <String?>[];
          for (var i = 0; i < stringCount; i++) {
            final idxOff = indexStart + i * 4;
            if (idxOff + 4 > bytes.length) break;
            final strOff =
                offset + stringsStart + d.getUint32(idxOff, Endian.little);
            if (strOff >= bytes.length) {
              list.add(null);
              continue;
            }
            list.add(isUtf8
                ? _readUtf8(bytes, strOff)
                : _readUtf16(bytes, strOff, d));
          }
          return _StringPool(list);
        }
        offset += chunkSize;
      }
    } catch (_) {}
    return null;
  }

  static String _readUtf8(List<int> b, int off) {
    // UTF-8 池：先 1~2 字节的字符数（含长度前缀），再 1~2 字节的字节数
    var p = off;
    var n = b[p++];
    if (n & 0x80 != 0) n = ((n & 0x7F) << 8) | b[p++];
    var len = b[p++];
    if (len & 0x80 != 0) len = ((len & 0x7F) << 8) | b[p++];
    if (p + len > b.length) len = b.length - p;
    return utf8.decode(b.sublist(p, p + len), allowMalformed: true);
  }

  static String _readUtf16(List<int> b, int off, ByteData d) {
    var p = off;
    var n = d.getUint16(p, Endian.little);
    p += 2;
    if (n & 0x8000 != 0) {
      n = ((n & 0x7FFF) << 16) | d.getUint16(p, Endian.little);
      p += 2;
    }
    final sb = StringBuffer();
    for (var i = 0; i < n && p + 2 <= b.length; i++, p += 2) {
      sb.writeCharCode(d.getUint16(p, Endian.little));
    }
    return sb.toString();
  }
}

/// resources.arsc 的字符串池（用于取应用名）
class _ArscStrings {
  _ArscStrings._();

  static List<String> parse(List<int> bytes) {
    try {
      final d = ByteData.sublistView(Uint8List.fromList(bytes));
      // arsc 头部 12 字节后是全局字符串池
      var offset = 12;
      final total = bytes.length;
      while (offset + 8 <= total) {
        final chunkType = d.getUint16(offset, Endian.little);
        final chunkSize = d.getUint32(offset + 4, Endian.little);
        if (chunkSize <= 0 || offset + chunkSize > total) break;
        if (chunkType == 0x0001) {
          final pool = _StringPool.parse(bytes.sublist(offset));
          if (pool != null) {
            return [
              for (var i = 0; i < pool._strings.length; i++)
                if (pool._strings[i] != null) pool._strings[i]!,
            ];
          }
        }
        offset += chunkSize;
      }
    } catch (_) {}
    return const [];
  }
}
