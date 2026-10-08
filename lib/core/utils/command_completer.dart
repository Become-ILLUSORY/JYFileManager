// 命令补全：为终端提供命令名、路径、选项的候选。
//
// 说明：Android 上应用能调用的 shell 通常是 toybox/busybox，不带 bash 的
// 补全机制，所以补全由应用侧实现 —— 拿到当前输入的词，判断它属于
// 命令位置还是参数位置，再给出候选。
import 'dart:io';

/// 一个补全候选
class Completion {
  const Completion(this.value, {this.description = ''});

  /// 补全后的文本
  final String value;

  /// 说明（显示在候选列表右侧）
  final String description;
}

class CommandCompleter {
  CommandCompleter._();

  /// 常见命令表（Android/toybox 上通常可用的）
  static const Map<String, String> commonCommands = {
    'ls': '列出目录内容',
    'cd': '切换目录',
    'pwd': '显示当前目录',
    'cat': '查看文件内容',
    'echo': '输出文本',
    'mkdir': '创建目录',
    'rmdir': '删除空目录',
    'rm': '删除文件',
    'cp': '复制',
    'mv': '移动/重命名',
    'touch': '创建空文件',
    'ln': '创建链接',
    'chmod': '修改权限',
    'chown': '修改所有者',
    'find': '查找文件',
    'grep': '文本搜索',
    'head': '查看开头',
    'tail': '查看结尾',
    'wc': '统计行数/字数',
    'sort': '排序',
    'uniq': '去重',
    'sed': '流编辑器',
    'awk': '文本处理',
    'tr': '字符转换',
    'cut': '按列截取',
    'diff': '对比文件',
    'du': '统计目录大小',
    'df': '查看磁盘空间',
    'stat': '查看文件信息',
    'file': '识别文件类型',
    'basename': '取文件名',
    'dirname': '取目录名',
    'readlink': '读取链接目标',
    'date': '显示日期时间',
    'sleep': '延时',
    'ps': '查看进程',
    'top': '进程监视',
    'kill': '结束进程',
    'id': '查看用户身份',
    'whoami': '显示当前用户',
    'uname': '系统信息',
    'uptime': '运行时间',
    'env': '环境变量',
    'export': '设置环境变量',
    'which': '查找命令位置',
    'clear': '清屏',
    'exit': '退出终端',
    'su': '切换为 root',
    'mount': '查看/挂载文件系统',
    'umount': '卸载文件系统',
    'dd': '按块复制',
    'tar': '打包/解包',
    'gzip': 'gzip 压缩',
    'zip': 'zip 压缩',
    'unzip': '解压 zip',
    'md5sum': '计算 MD5',
    'sha1sum': '计算 SHA1',
    'sha256sum': '计算 SHA256',
    'base64': 'base64 编解码',
    'ping': '网络连通测试',
    'netstat': '网络状态',
    'ifconfig': '网络接口',
    'ip': '网络配置',
    'getprop': '读取系统属性',
    'setprop': '设置系统属性',
    'pm': '包管理',
    'am': '活动管理',
    'dumpsys': '系统服务信息',
    'logcat': '查看日志',
    'input': '模拟输入',
    'screencap': '截屏',
    'wm': '窗口管理',
    'svc': '服务控制',
    'settings': '读写系统设置',
    'reboot': '重启设备',
    'sync': '同步文件系统',
  };

  /// 常见选项（按命令）
  static const Map<String, List<String>> commandOptions = {
    'ls': ['-l', '-a', '-h', '-la', '-lah', '-R', '-t', '-S'],
    'rm': ['-r', '-f', '-rf', '-i'],
    'cp': ['-r', '-f', '-a', '-v'],
    'mv': ['-f', '-v'],
    'mkdir': ['-p'],
    'chmod': ['-R', '755', '644', '777'],
    'grep': ['-i', '-r', '-n', '-v', '-E'],
    'find': ['-name', '-type', '-maxdepth', '-exec'],
    'head': ['-n'],
    'tail': ['-n', '-f'],
    'ps': ['-A', '-ef', '-aux'],
    'tar': ['-czf', '-xzf', '-tzf', '-cvf', '-xvf'],
    'du': ['-h', '-s', '-sh'],
    'df': ['-h'],
    'cat': ['-n'],
  };

  /// 根据当前输入行计算候选
  ///
  /// [line] 整行输入，[cursor] 光标位置，[cwd] 当前工作目录。
  static Future<List<Completion>> complete(
    String line, {
    required int cursor,
    required String cwd,
  }) async {
    final before = line.substring(0, cursor.clamp(0, line.length));
    final tokens = before.split(RegExp(r'\s+'));

    // 第一个词 → 补全命令
    if (tokens.length <= 1) {
      final prefix = tokens.isEmpty ? '' : tokens.first;
      return [
        for (final e in commonCommands.entries)
          if (e.key.startsWith(prefix))
            Completion(e.key, description: e.value),
      ];
    }

    final cmd = tokens.first;
    final current = tokens.last;

    // 以 - 开头 → 补全选项
    if (current.startsWith('-')) {
      final opts = commandOptions[cmd] ?? const [];
      return [
        for (final o in opts)
          if (o.startsWith(current)) Completion(o),
      ];
    }

    // 否则补全路径
    return _completePath(current, cwd);
  }

  /// 路径补全：列出匹配的目录项
  static Future<List<Completion>> _completePath(
    String prefix,
    String cwd,
  ) async {
    try {
      // 拆出目录部分与待补全的文件名前缀
      final lastSlash = prefix.lastIndexOf('/');
      String dirPart;
      String namePart;
      if (lastSlash >= 0) {
        dirPart = prefix.substring(0, lastSlash + 1);
        namePart = prefix.substring(lastSlash + 1);
      } else {
        dirPart = '';
        namePart = prefix;
      }

      final targetDir = dirPart.isEmpty
          ? cwd
          : (dirPart.startsWith('/') ? dirPart : '$cwd/$dirPart');

      final dir = Directory(targetDir);
      if (!dir.existsSync()) return const [];

      final out = <Completion>[];
      for (final entity in dir.listSync()) {
        final name = entity.path.split('/').last;
        if (name.isEmpty) continue;
        if (namePart.isNotEmpty && !name.startsWith(namePart)) continue;

        final isDir = entity is Directory;
        out.add(Completion(
          '$dirPart$name${isDir ? '/' : ''}',
          description: isDir ? '目录' : _sizeLabel(entity),
        ));
        if (out.length >= 60) break;
      }
      out.sort((a, b) {
        // 目录优先，再按名称
        final ad = a.value.endsWith('/');
        final bd = b.value.endsWith('/');
        if (ad != bd) return ad ? -1 : 1;
        return a.value.toLowerCase().compareTo(b.value.toLowerCase());
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String _sizeLabel(FileSystemEntity e) {
    try {
      final len = (e as File).lengthSync();
      if (len < 1024) return '${len}B';
      if (len < 1024 * 1024) return '${(len / 1024).toStringAsFixed(1)}KB';
      return '${(len / 1024 / 1024).toStringAsFixed(1)}MB';
    } catch (_) {
      return '';
    }
  }
}
