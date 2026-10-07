// 文本文件识别：判断某个文件是否可以用内置编辑器直接打开，
// 以及它应该用什么语法高亮。
//
// 设计取舍：
//   - 优先看**扩展名**（最准），无扩展名时看文件名（Makefile、Dockerfile…）
//   - 不认识扩展名时，回退到「按内容嗅探」：读前几 KB，若不像二进制就当文本
//     （这样 .conf、.log、无后缀配置等也能打开，而不是一律甩给系统应用）
//   - 明确排除常见二进制格式，避免把图片/APK 当文本打开
import 'dart:typed_data';

/// 一个文本类型：扩展名 → 高亮语言 + 展示名
class TextKind {
  const TextKind(this.language, this.label, {this.aliases = const []});

  /// re_highlight 的语言标识（null 表示不高亮，纯文本）
  final String? language;

  /// 界面上展示的类型名，如「Python 脚本」
  final String label;

  /// 同一语言的其它扩展名
  final List<String> aliases;
}

/// 压缩包格式识别
class ArchiveKinds {
  ArchiveKinds._();

  /// 可浏览/解压的压缩包扩展名
  static const Set<String> browsable = {
    'zip', 'jar', 'war', 'apk', 'apks', 'xapk', 'aar', 'egg', 'whl',
    'tar', 'gz', 'tgz', 'bz2', 'tbz', 'tbz2', 'xz', 'txz', 'zst', 'lz4',
    '7z', 'rar', 'iso', 'cab', 'arj', 'lzh',
  };

  static String extensionOf(String name) => TextFileKinds.extensionOf(name);

  /// 是否为压缩包（按扩展名判断，含 .tar.gz 这类双扩展名）
  static bool isArchive(String name) {
    final lower = name.toLowerCase();
    // 双扩展名先判
    for (final two in const ['tar.gz', 'tar.bz2', 'tar.xz', 'tar.zst', 'tar.lz4']) {
      if (lower.endsWith('.$two')) return true;
    }
    return browsable.contains(extensionOf(lower));
  }
}

/// 文本文件识别工具
class TextFileKinds {
  TextFileKinds._();

  /// 扩展名（小写，不含点） → 类型
  static const Map<String, TextKind> byExtension = {
    // ---- 纯文本 / 配置 ----
    'txt': TextKind(null, '文本文件'),
    'text': TextKind(null, '文本文件'),
    'log': TextKind(null, '日志文件'),
    'md': TextKind('markdown', 'Markdown 文档'),
    'markdown': TextKind('markdown', 'Markdown 文档'),
    'rst': TextKind(null, 'reStructuredText'),
    'ini': TextKind('ini', 'INI 配置'),
    'cfg': TextKind('ini', '配置文件'),
    'conf': TextKind('ini', '配置文件'),
    'properties': TextKind('properties', 'Properties 配置'),
    'toml': TextKind('ini', 'TOML 配置'),
    'env': TextKind(null, '环境变量文件'),
    'editorconfig': TextKind('ini', 'EditorConfig'),

    // ---- 结构化数据 ----
    'json': TextKind('json', 'JSON 数据'),
    'jsonc': TextKind('json', 'JSON with Comments'),
    'json5': TextKind('json', 'JSON5 数据'),
    'yaml': TextKind('yaml', 'YAML 配置'),
    'yml': TextKind('yaml', 'YAML 配置'),
    'xml': TextKind('xml', 'XML 文档'),
    'plist': TextKind('xml', 'Property List'),
    'svg': TextKind('xml', 'SVG 矢量图'),
    'csv': TextKind(null, 'CSV 表格'),
    'tsv': TextKind(null, 'TSV 表格'),
    'lock': TextKind(null, '锁文件'),

    // ---- 编程语言 ----
    'c': TextKind('c', 'C 源文件'),
    'h': TextKind('c', 'C 头文件'),
    'cpp': TextKind('cpp', 'C++ 源文件'),
    'cc': TextKind('cpp', 'C++ 源文件'),
    'cxx': TextKind('cpp', 'C++ 源文件'),
    'hpp': TextKind('cpp', 'C++ 头文件'),
    'hh': TextKind('cpp', 'C++ 头文件'),
    'java': TextKind('java', 'Java 源文件'),
    'kt': TextKind('kotlin', 'Kotlin 源文件'),
    'kts': TextKind('kotlin', 'Kotlin 脚本'),
    'py': TextKind('python', 'Python 脚本'),
    'pyw': TextKind('python', 'Python 脚本'),
    'pyi': TextKind('python', 'Python 存根'),
    'js': TextKind('javascript', 'JavaScript 脚本'),
    'mjs': TextKind('javascript', 'JavaScript 模块'),
    'cjs': TextKind('javascript', 'JavaScript 模块'),
    'jsx': TextKind('javascript', 'React JSX'),
    'ts': TextKind('typescript', 'TypeScript 脚本'),
    'tsx': TextKind('typescript', 'React TSX'),
    'dart': TextKind('dart', 'Dart 源文件'),
    'go': TextKind('go', 'Go 源文件'),
    'rs': TextKind('rust', 'Rust 源文件'),
    'rb': TextKind('ruby', 'Ruby 脚本'),
    'php': TextKind('php', 'PHP 脚本'),
    'swift': TextKind('swift', 'Swift 源文件'),
    'cs': TextKind('csharp', 'C# 源文件'),
    'scala': TextKind('scala', 'Scala 源文件'),
    'lua': TextKind('lua', 'Lua 脚本'),
    'pl': TextKind('perl', 'Perl 脚本'),
    'r': TextKind('r', 'R 脚本'),
    'm': TextKind('objectivec', 'Objective-C 源文件'),
    'mm': TextKind('objectivec', 'Objective-C++ 源文件'),
    'asm': TextKind('x86asm', '汇编源文件'),
    's': TextKind('x86asm', '汇编源文件'),

    // ---- 脚本 / 构建 ----
    'sh': TextKind('bash', 'Shell 脚本'),
    'bash': TextKind('bash', 'Bash 脚本'),
    'zsh': TextKind('bash', 'Zsh 脚本'),
    'fish': TextKind('bash', 'Fish 脚本'),
    'bat': TextKind('dos', 'Windows 批处理'),
    'cmd': TextKind('dos', 'Windows 批处理'),
    'ps1': TextKind('powershell', 'PowerShell 脚本'),
    'gradle': TextKind('groovy', 'Gradle 构建脚本'),
    'groovy': TextKind('groovy', 'Groovy 脚本'),
    'cmake': TextKind('cmake', 'CMake 脚本'),
    'mk': TextKind('makefile', 'Makefile'),
    'makefile': TextKind('makefile', 'Makefile'),
    'dockerfile': TextKind('dockerfile', 'Dockerfile'),
    'pro': TextKind('makefile', 'Qt 工程文件'),

    // ---- Web / 样式 ----
    'html': TextKind('xml', 'HTML 文档'),
    'htm': TextKind('xml', 'HTML 文档'),
    'css': TextKind('css', 'CSS 样式表'),
    'scss': TextKind('scss', 'SCSS 样式表'),
    'less': TextKind('less', 'Less 样式表'),
    'vue': TextKind('xml', 'Vue 组件'),

    // ---- 数据库 / 查询 ----
    'sql': TextKind('sql', 'SQL 脚本'),
    'db': TextKind(null, '数据库文件'),

    // ---- 其它常见 ----
    'gitignore': TextKind(null, 'Git 忽略规则'),
    'gitattributes': TextKind(null, 'Git 属性'),
    'gitmodules': TextKind('ini', 'Git 子模块'),
    'patch': TextKind('diff', '补丁文件'),
    'diff': TextKind('diff', '差异文件'),
    'pem': TextKind(null, '证书文件'),
    'crt': TextKind(null, '证书文件'),
    'key': TextKind(null, '密钥文件'),
    'pub': TextKind(null, '公钥文件'),
    'pemkey': TextKind(null, '密钥文件'),
  };

  /// 无扩展名时按文件名判断
  static const Map<String, TextKind> byFileName = {
    'makefile': TextKind('makefile', 'Makefile'),
    'dockerfile': TextKind('dockerfile', 'Dockerfile'),
    'cmakelists.txt': TextKind('cmake', 'CMake 脚本'),
    'gradlew': TextKind('bash', 'Gradle Wrapper'),
    'gitignore': TextKind(null, 'Git 忽略规则'),
    'gitattributes': TextKind(null, 'Git 属性'),
    'editorconfig': TextKind('ini', 'EditorConfig'),
    '.bashrc': TextKind('bash', 'Bash 配置'),
    '.zshrc': TextKind('bash', 'Zsh 配置'),
    '.profile': TextKind('bash', 'Shell 配置'),
    'hosts': TextKind(null, 'hosts 文件'),
    'fstab': TextKind(null, 'fstab 文件'),
    'readme': TextKind('markdown', '说明文档'),
    'license': TextKind(null, '许可证'),
    'authors': TextKind(null, '作者列表'),
  };

  /// 明确按二进制处理的扩展名（避免误当文本打开）
  static const Set<String> binaryExtensions = {
    // 图片
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'ico', 'tif', 'tiff',
    'heic', 'heif', 'avif', 'psd', 'raw',
    // 音视频
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'opus', 'wma',
    // 注意：'.ts' 有歧义（TypeScript 源文件 vs MPEG-TS 视频流）。
    // 这里**不**把它当二进制 —— 代码文件远比视频流常见，
    // 真的遇到 MPEG-TS 时由内容嗅探（含 NUL 字节）兜底识别。
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', '3gp', 'm4v',
    // 压缩包
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'zst', 'lz4', 'jar',
    'apk', 'apks', 'xapk', 'aar', 'war', 'deb', 'rpm', 'iso', 'img',
    // 文档
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods',
    'epub', 'mobi', 'azw3',
    // 可执行 / 库
    'exe', 'dll', 'so', 'dylib', 'bin', 'o', 'a', 'class', 'dex', 'elf',
    'wasm', 'pyc', 'pyo',
    // 数据库 / 其它
    'db', 'sqlite', 'sqlite3', 'mdb', 'dat', 'pak', 'ttf', 'otf', 'woff',
    'woff2', 'eot',
  };

  /// 取扩展名（小写，不含点；没有则返回空串）
  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// 判断文件是否应当用内置编辑器打开。
  ///
  /// 只依据名字与扩展名（不读内容），用于「点击时是否直接进编辑器」的快速判断。
  static bool isTextByName(String name) {
    final lower = name.toLowerCase();
    final ext = extensionOf(lower);

    if (binaryExtensions.contains(ext)) return false;
    if (byExtension.containsKey(ext)) return true;
    if (byFileName.containsKey(lower)) return true;

    // 点开头的隐藏配置文件（.gitignore / .env / .npmrc…）当作文本
    if (lower.startsWith('.') && !lower.contains('.')) return true;
    if (lower.startsWith('.') && ext.isNotEmpty) {
      // .env.local / .eslintrc.json 之类
      if (byExtension.containsKey(ext)) return true;
      return !binaryExtensions.contains(ext);
    }
    return false;
  }

  /// 查询类型信息；未知返回 null
  static TextKind? kindOf(String name) {
    final lower = name.toLowerCase();
    final ext = extensionOf(lower);
    return byExtension[ext] ?? byFileName[lower];
  }

  /// 内容嗅探：判断一段字节是否像文本。
  ///
  /// 用于没有扩展名、或扩展名不认识的文件 —— 这样 `.conf`、无后缀配置
  /// 也能用编辑器打开，而不是一律甩给系统应用。
  static bool looksLikeText(Uint8List bytes, {int sampleSize = 8192}) {
    final n = bytes.length < sampleSize ? bytes.length : sampleSize;
    if (n == 0) return true; // 空文件当文本
    var suspicious = 0;
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      if (b == 0) return false; // NUL 字节 → 二进制
      // 允许 \t(9) \n(10) \v(11) \f(12) \r(13)
      if (b < 0x09 || (b > 0x0D && b < 0x20)) suspicious++;
    }
    return suspicious / n <= 0.1;
  }
}
