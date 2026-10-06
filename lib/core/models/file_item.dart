// 文件条目模型 —— 统一表示本地/远程文件系统中的一个条目
// 刻意不依赖 dart:io：模型与 UI 层保持跨平台（Web 预览 / 远程文件系统复用）。

/// 文件类型枚举
enum FileKind {
  directory,
  file,
  link,
  unknown,
}

/// 统一文件条目模型。
///
/// 本地文件通过 [FileItem.fromFileStat] 构建；远程文件系统（FTP/WebDAV）
/// 通过构造器直接构建。所有 UI 与操作都基于本模型，与具体文件系统无关。
class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final bool isLink;
  final String? linkTarget;
  final int size;
  final DateTime modified;
  final DateTime? accessed;
  final DateTime? changed;

  /// Unix 权限位（本地文件可用，远程为 null）
  final int? mode;

  /// 归属用户/组（本地文件可用）
  final int? uid;
  final int? gid;

  const FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isLink = false,
    this.linkTarget,
    this.size = 0,
    required this.modified,
    this.accessed,
    this.changed,
    this.mode,
    this.uid,
    this.gid,
  });

  /// 路径的最后一段（供本地实现构造条目时复用）
  static String basenameOf(String path) {
    if (path == '/') return '/';
    var p = path;
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    final idx = p.lastIndexOf('/');
    return idx < 0 ? p : p.substring(idx + 1);
  }

  /// 扩展名（小写，不含点）；无扩展名返回空串
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// 文件名主干（去掉扩展名）
  String get baseName {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  FileKind get kind {
    if (isLink) return FileKind.link;
    if (isDirectory) return FileKind.directory;
    return FileKind.file;
  }

  bool get isHidden => name.startsWith('.');

  /// 是否可作为压缩包打开
  bool get isArchive => isArchiveExtension(extension);

  /// 是否是图片
  bool get isImage => const {
        'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
        'svg', 'ico', 'tiff', 'tif', 'avif', 'raw', 'dng',
      }.contains(extension);

  /// 是否是视频
  bool get isVideo => const {
        'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', '3gp',
        'm4v', 'ts', 'rmvb', 'rm', 'mpg', 'mpeg', 'm2ts',
      }.contains(extension);

  /// 是否是音频
  bool get isAudio => const {
        'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus',
        'ape', 'amr', 'mid', 'midi',
      }.contains(extension);

  /// 是否是 APK
  bool get isApk => extension == 'apk';

  /// 是否是代码/文本类文件
  bool get isText => isTextExtension(extension);

  /// 可读权限（本地）
  bool get canRead => mode == null || (mode! & 0x100) != 0 || (mode! & 0x20) != 0;

  /// 权限字符串 rwxr-xr-x
  String get modeString {
    if (mode == null) return '---------';
    final m = mode!;
    final buf = StringBuffer();
    buf.write((m & 0x100) != 0 ? 'r' : '-');
    buf.write((m & 0x80) != 0 ? 'w' : '-');
    buf.write((m & 0x40) != 0 ? 'x' : '-');
    buf.write((m & 0x20) != 0 ? 'r' : '-');
    buf.write((m & 0x10) != 0 ? 'w' : '-');
    buf.write((m & 0x8) != 0 ? 'x' : '-');
    buf.write((m & 0x4) != 0 ? 'r' : '-');
    buf.write((m & 0x2) != 0 ? 'w' : '-');
    buf.write((m & 0x1) != 0 ? 'x' : '-');
    return buf.toString();
  }

  /// 八进制权限串
  String get modeOctal {
    if (mode == null) return '----------';
    return '0${(mode! & 0xFFF).toRadixString(8).padLeft(3, '0')}';
  }

  FileItem copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    bool? isLink,
    String? linkTarget,
    int? size,
    DateTime? modified,
    int? mode,
  }) {
    return FileItem(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      isLink: isLink ?? this.isLink,
      linkTarget: linkTarget ?? this.linkTarget,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      accessed: accessed,
      changed: changed,
      mode: mode ?? this.mode,
      uid: uid,
      gid: gid,
    );
  }

  @override
  String toString() => 'FileItem($path, dir=$isDirectory, size=$size)';
}

/// 判断扩展名是否是压缩包格式
bool isArchiveExtension(String ext) => const {
      'zip', 'jar', 'apk', 'aar', 'war', 'ear', 'xpi', 'crx', 'ipa',
      'tar', 'gz', 'tgz', 'bz2', 'tbz', 'tbz2', 'xz', 'txz', 'lzma',
      '7z', 'rar', 'zst', 'lz4', 'cab', 'iso', 'zipx', 'zpaq',
    }.contains(ext);

/// 判断扩展名是否是文本/代码格式
bool isTextExtension(String ext) => const {
      // 纯文本
      'txt', 'text', 'log', 'md', 'markdown', 'rst', 'csv', 'tsv',
      // 配置
      'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'properties',
      'prop', 'env', 'lock', 'gitignore', 'editorconfig',
      // 代码
      'dart', 'java', 'kt', 'kts', 'groovy', 'gradle', 'scala',
      'c', 'h', 'cpp', 'cc', 'cxx', 'hpp', 'hh', 'm', 'mm',
      'cs', 'go', 'rs', 'swift', 'py', 'rb', 'php', 'pl', 'pm',
      'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'vue', 'svelte',
      'html', 'htm', 'xhtml', 'css', 'scss', 'sass', 'less',
      'sql', 'sh', 'bash', 'zsh', 'fish', 'bat', 'cmd', 'ps1', 'psm1',
      'lua', 'r', 'jl', 'hs', 'clj', 'cljs', 'ex', 'exs', 'erl', 'hrl',
      'f90', 'f95', 'asm', 's', 'v', 'sv', 'vhd', 'tcl', 'awk', 'sed',
      // 文档/数据
      'smali', 'sml', 'diff', 'patch', 'svg', 'plist', 'proto', 'graphql',
      'gql', 'tf', 'hcl', 'dockerfile', 'makefile', 'cmake', 'mk',
    }.contains(ext);

/// 是否为已知的二进制扩展名
bool isBinaryExtension(String ext) => const {
      'apk', 'jar', 'dex', 'odex', 'vdex', 'art', 'oat', 'so', 'dll', 'exe',
      'bin', 'img', 'iso', 'zip', 'rar', '7z', 'gz', 'xz', 'bz2', 'zst',
      'mp3', 'mp4', 'mkv', 'avi', 'mov', 'wav', 'flac', 'ogg', 'webm',
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico', 'heic', 'avif',
      'ttf', 'otf', 'woff', 'woff2', 'db', 'sqlite', 'mdb', 'class',
      'pyc', 'pyo', 'wasm', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt',
      'pptx', 'epub', 'mobi', 'azw3', 'dat', 'pak', 'assets',
    }.contains(ext);
