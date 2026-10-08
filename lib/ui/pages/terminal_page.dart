// 终端模拟器。
//
// 交互形态参考成熟的终端 App：
//   - 全屏黑底，输出区就是整个屏幕（不是上方输出 + 下方输入框两截）
//   - 提示行形如 `路径 $ `，光标就在这一行内联显示，输入直接跟在后面
//   - 底部是**终端功能键栏**（Esc/Tab/Ctrl/方向键等软键盘没有的键）
//   - 补全候选显示在提示行上方，点击即插入
//
// 实现：Process.start 起真实 sh；提权就绪时用 su。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/utils/ansi.dart';
import '../../core/utils/command_completer.dart';
import '../../services/privilege.dart';
import '../widgets/terminal_key_bar.dart';

/// 打开终端
Future<void> showTerminalPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const TerminalPage(),
      fullscreenDialog: true,
    ),
  );
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _output = <_Line>[];
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  Process? _process;
  IOSink? _stdin;

  final _history = <String>[];
  int _historyIndex = -1;

  List<Completion> _completions = const [];

  /// Ctrl 激活态：下一个字母会转成控制字符
  bool _ctrlActive = false;

  bool _running = false;
  String _cwd = '/';

  /// 终端配色
  static const _bg = Color(0xFF000000);
  static const _fg = Color(0xFFD8DEE9);
  static const _accent = Color(0xFF7FD1FF);
  static const _dim = Color(0xFF8B949E);
  static const _err = Color(0xFFFF8A80);

  @override
  void initState() {
    super.initState();
    _cwd = Directory.current.path;
    _input.addListener(() => _refreshCompletions(_input.text));
    _startShell();
  }

  bool get _isRoot => PrivilegeManager.instance.isActive;

  @override
  void dispose() {
    _stdin?.close();
    _process?.kill();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- shell ----------

  Future<void> _startShell() async {
    try {
      // 用 sh -c 先注入环境与别名，再进入交互式 sh：
      //   · ls 默认带颜色（--color=auto 在非 tty 下不生效，这里显式打开）
      //   · 常见的彩色命令都走 --color=always
      //   · 设置 LS_COLORS 覆盖目录/可执行/链接/压缩包等的颜色
      const init = r'''
export TERM=xterm-256color
export CLICOLOR=1
export LS_COLORS="di=1;34:ln=1;36:so=1;35:pi=33:ex=1;32:bd=1;33:cd=1;33:su=37;41:sg=30;43:tw=30;42:ow=34;42:*.zip=1;31:*.apk=1;31:*.tar=1;31:*.gz=1;31:*.7z=1;31:*.rar=1:*.jpg=1;35:*.png=1;35:*.mp4=1;35:*.mp3=1;35"
alias ls='ls --color=always'
alias ll='ls -l --color=always'
alias la='ls -la --color=always'
alias l='ls -CF --color=always'
alias grep='grep --color=always'
alias dir='ls -la --color=always'
''';
      final args = _isRoot
          ? ['-c', '$init\nexec sh']
          : ['-c', '$init\nexec sh'];
      final proc = await Process.start(
        _isRoot ? 'su' : 'sh',
        args,
        workingDirectory: _cwd,
        environment: {
          'TERM': 'xterm-256color',
          'CLICOLOR': '1',
          'LANG': 'C.UTF-8',
        },
      );

      _process = proc;
      _stdin = proc.stdin;
      setState(() => _running = true);

      proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((c) => _append(c, _LineKind.output));
      proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((c) => _append(c, _LineKind.error));

      proc.exitCode.then((code) {
        if (!mounted) return;
        setState(() => _running = false);
        _print('[shell 已退出，代码 $code]', _LineKind.hint);
      });
    } catch (e) {
      setState(() => _running = false);
      _print('无法启动 shell：$e', _LineKind.error);
    }
  }

  void _print(String text, _LineKind kind) {
    setState(() => _output.add(_Line(text, kind)));
    _scrollToEnd();
  }

  void _append(String chunk, _LineKind kind) {
    if (chunk.isEmpty) return;
    setState(() {
      if (_output.isNotEmpty && _output.last.partial) {
        _output.last.text += chunk;
      } else {
        _output.add(_Line(chunk, kind, partial: true));
      }
      if (chunk.endsWith('\n')) _output.last.partial = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ---------- 输入 ----------

  Future<void> _submit() async {
    final cmd = _input.text;
    if (cmd.trim().isEmpty) return;

    // 先把焦点要回来再清空输入：清空会触发 controller 通知，
    // 若此时输入框已失焦，键盘就会收起、命令输出被键盘挡住。
    _keepKeyboard();

    _input.clear();
    setState(() => _completions = const []);
    _history.add(cmd);
    _historyIndex = -1;

    // 回显：提示行 + 命令（输出留在当前页面）
    _print('${_promptText()}$cmd', _LineKind.command);

    if (cmd.trim() == 'clear') {
      setState(() => _output.clear());
      return;
    }
    if (cmd.trim() == 'exit') {
      _process?.kill();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final stdin = _stdin;
    if (stdin == null || !_running) {
      _print('shell 未就绪', _LineKind.error);
      return;
    }
    try {
      if (cmd.trim() == 'cd' || cmd.trim().startsWith('cd ')) {
        final target =
            cmd.trim() == 'cd' ? '/' : cmd.trim().substring(3).trim();
        _cwd = _normalizePath(
          target.startsWith('/') ? target : '$_cwd/$target',
        );
        setState(() {});
      }
      stdin.writeln(cmd);
      await stdin.flush();
    } catch (e) {
      _print('执行失败：$e', _LineKind.error);
    }
    _keepKeyboard();
  }

  void _keepKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_inputFocus.hasFocus) _inputFocus.requestFocus();
    });
  }

  /// 提示串：显示**完整绝对路径**，形如 `/storage/emulated/0 $ `
  ///
  /// 之前把 /storage/emulated/0 缩写成 ~ 并且路径未规范化，
  /// 会出现 `//sdcard/TV/ $` 这种双斜杠 + 多余末尾斜杠。
  String _promptText() => '${_normalizePath(_cwd)} \$ ';

  /// 规范化路径：折叠重复斜杠、去掉末尾斜杠（根目录除外）
  String _normalizePath(String p) {
    var s = p.trim();
    if (s.isEmpty) return '/';
    // 折叠连续斜杠
    s = s.replaceAll(RegExp(r'/+'), '/');
    // 去掉末尾斜杠（根目录除外）
    if (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> _refreshCompletions(String text) async {
    if (text.trim().isEmpty) {
      if (_completions.isNotEmpty) setState(() => _completions = const []);
      return;
    }
    final cursor =
        _input.selection.baseOffset >= 0 ? _input.selection.baseOffset : text.length;
    final list =
        await CommandCompleter.complete(text, cursor: cursor, cwd: _cwd);
    if (!mounted) return;
    if (list.length == 1 && list.first.value == text.trim()) {
      setState(() => _completions = const []);
      return;
    }
    setState(() => _completions = list);
  }

  void _applyCompletion(Completion c) {
    final text = _input.text;
    final cursor =
        _input.selection.baseOffset >= 0 ? _input.selection.baseOffset : text.length;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final m = RegExp(r'(\S*)$').firstMatch(before);
    final wordStart = m != null ? m.start : before.length;
    final head = before.substring(0, wordStart);

    final next = '$head${c.value}$after';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: head.length + c.value.length),
    );
    _inputFocus.requestFocus();
    _refreshCompletions(next);
  }

  /// Tab 补全：立刻算一次候选并应用
  ///
  /// 单候选 → 直接补上；多候选 → 列出候选让用户选（同时把公共前缀补全）。
  Future<void> _completeNow() async {
    final text = _input.text;
    final cursor = _input.selection.baseOffset >= 0
        ? _input.selection.baseOffset
        : text.length;
    if (text.trim().isEmpty) {
      _snackTip('先输入命令或路径，再按 Tab 补全');
      return;
    }

    final list = await CommandCompleter.complete(
      text,
      cursor: cursor,
      cwd: _cwd,
    );
    if (!mounted) return;

    if (list.isEmpty) {
      _snackTip('没有匹配的补全项');
      return;
    }
    if (list.length == 1) {
      _applyCompletion(list.first);
      return;
    }

    // 多候选：先补公共前缀，再把候选列出来供选择
    final common = _commonPrefix(list.map((e) => e.value).toList());
    final current = _currentWord(text, cursor);
    if (common.length > current.length) {
      _applyCompletion(Completion(common));
    }
    setState(() => _completions = list);
  }

  /// 取当前正在输入的词
  String _currentWord(String text, int cursor) {
    final before = text.substring(0, cursor.clamp(0, text.length));
    final m = RegExp(r'(\S*)$').firstMatch(before);
    return m?.group(1) ?? '';
  }

  /// 一组字符串的公共前缀
  String _commonPrefix(List<String> items) {
    if (items.isEmpty) return '';
    var prefix = items.first;
    for (final s in items.skip(1)) {
      var i = 0;
      while (i < prefix.length && i < s.length && prefix[i] == s[i]) {
        i++;
      }
      prefix = prefix.substring(0, i);
      if (prefix.isEmpty) break;
    }
    return prefix;
  }

  /// 轻提示（终端里用 SnackBar 会挡键盘，这里改用输出区提示行）
  void _snackTip(String msg) {
    _print('# $msg', _LineKind.hint);
  }

  void _useHistory(int delta) {
    if (_history.isEmpty) return;
    var idx = _historyIndex + delta;
    if (idx < 0) idx = 0;
    if (idx >= _history.length) idx = _history.length - 1;
    _historyIndex = idx;
    _input.text = _history[idx];
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  // ---------- 功能键 ----------

  void _onSend(String data) {
    final stdin = _stdin;
    if (stdin == null || !_running) return;
    stdin.write(data);
    stdin.flush();
    _keepKeyboard();
  }

  void _onAction(String action) {
    switch (action) {
      case 'tab':
        // Tab 时**实时**重新计算候选再补全：
        // 依赖输入监听里的异步结果可能还没算完，点了没反应。
        unawaited(_completeNow());
      case 'up':
        _useHistory(-1);
      case 'down':
        _useHistory(1);
      case 'enter':
        _submit();
      case 'ctrl':
        setState(() => _ctrlActive = !_ctrlActive);
      case 'more':
        _showMoreKeys();
      case 'left':
      case 'right':
        // 移动光标：软键盘一般已支持，这里兜底
        final pos = _input.selection.baseOffset;
        final target = action == 'left' ? pos - 1 : pos + 1;
        if (target >= 0 && target <= _input.text.length) {
          _input.selection = TextSelection.collapsed(offset: target);
        }
    }
    _keepKeyboard();
  }

  /// 更多键：常见控制序列
  void _showMoreKeys() {
    const keys = <(String, String)>[
      ('Ctrl+C  中断', '\x03'),
      ('Ctrl+D  结束输入', '\x04'),
      ('Ctrl+L  清屏', '\x0c'),
      ('Ctrl+Z  挂起', '\x1a'),
      ('Ctrl+A  行首', '\x01'),
      ('Ctrl+E  行尾', '\x05'),
      ('Ctrl+U  清行', '\x15'),
      ('Ctrl+W  删词', '\x17'),
      ('F1', '\x1bOP'),
      ('F2', '\x1bOQ'),
      ('Delete', '\x1b[3~'),
      ('Insert', '\x1b[2~'),
      ('\\t 制表符', '\t'),
      ('|  管道', '|'),
      ('>  重定向', '>'),
      ('&  后台', ' &'),
    ];
    final colors = MiuixTheme.of(context).colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '更多按键',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in keys)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _onSend(k.$2);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          k.$1,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    // 键盘高度：加在整列底部，让功能键栏浮在键盘之上，
    // 这样输入行、功能键栏、命令输出三者同时可见。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: _bg,
      // 关闭系统自动避让，改由我们手动控制（避免内容被顶两次）
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildOutput()),
            _buildPromptLine(),
            TerminalKeyBar(
              onSend: _onSend,
              onAction: _onAction,
              ctrlActive: _ctrlActive,
            ),
            SizedBox(height: keyboard),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 44,
      color: const Color(0xFF0D0F12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded,
                size: 21, color: _fg),
          ),
          Expanded(
            child: Text(
              _running ? 'sh${_isRoot ? " (root)" : ""}' : 'shell 未运行',
              style: const TextStyle(
                fontSize: 13,
                color: _dim,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _output.clear()),
            icon: const Icon(Icons.cleaning_services_rounded,
                size: 19, color: _fg),
          ),
          IconButton(
            onPressed: () {
              _process?.kill();
              _output.clear();
              _print('shell 已重启', _LineKind.hint);
              _startShell();
            },
            icon: const Icon(Icons.refresh_rounded, size: 19, color: _fg),
          ),
        ],
      ),
    );
  }

  Widget _buildOutput() {
    return GestureDetector(
      onTap: () => _inputFocus.requestFocus(),
      child: Container(
        width: double.infinity,
        color: _bg,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          itemCount: _output.length,
          itemBuilder: (ctx, i) {
            final line = _output[i];
            final baseColor = switch (line.kind) {
              _LineKind.command => _accent,
              _LineKind.error => _err,
              _LineKind.hint => _dim,
              _LineKind.output => _fg,
            };
            final baseStyle = TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['monospace'],
              fontSize: 12.5,
              height: 1.35,
              color: baseColor,
            );

            // 普通输出里可能带 ANSI 颜色码（ls --color 等），
            // 解析成多段 TextSpan 渲染；其它类型（命令回显/错误/提示）
            // 用统一颜色，避免和自己的配色打架。
            if (line.kind != _LineKind.output) {
              return Text(line.text, style: baseStyle);
            }

            final spans = AnsiParser.parse(
              line.text,
              base: baseStyle,
              defaultColor: _fg,
            );
            if (spans.isEmpty) return const SizedBox.shrink();
            if (spans.length == 1) {
              return Text(spans.first.text, style: spans.first.style);
            }
            return Text.rich(TextSpan(children: [
              for (final s in spans) TextSpan(text: s.text, style: s.style),
            ]));
          },
        ),
      ),
    );
  }

  /// 提示行：`路径 $ 输入`，输入直接内联在提示串后面
  Widget _buildPromptLine() {
    return Container(
      color: _bg,
      padding: EdgeInsets.only(
        left: 10,
        right: 6,
        top: 6,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_completions.isNotEmpty) _buildCompletions(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 提示串（等宽，不换行）
              Text(
                _promptText(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['monospace'],
                  fontSize: 12.5,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.arrowUp):
                        _HistoryIntent(-1),
                    SingleActivator(LogicalKeyboardKey.arrowDown):
                        _HistoryIntent(1),
                    SingleActivator(LogicalKeyboardKey.tab): _CompleteIntent(),
                  },
                  child: Actions(
                    actions: {
                      _HistoryIntent: CallbackAction<_HistoryIntent>(
                        onInvoke: (intent) {
                          _useHistory(intent.delta);
                          return null;
                        },
                      ),
                      _CompleteIntent: CallbackAction<_CompleteIntent>(
                        onInvoke: (intent) {
                          _onAction('tab');
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      autofocus: true,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: ['monospace'],
                        fontSize: 12.5,
                        color: _fg,
                      ),
                      cursorColor: _accent,
                      cursorWidth: 8,
                      cursorHeight: 15,
                      autocorrect: false,
                      enableSuggestions: false,
                      // 键盘的回车键要能提交命令：
                      //   newline → 回车变成插入换行（错误）
                      //   send    → 回车触发 onSubmitted（正确）
                      // 提交后由 _keepKeyboard() 立刻把焦点要回来，
                      // 键盘不会收起，命令输出直接显示在当前页面。
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      // 单行显示：终端输入本来就是一行
                      maxLines: 1,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: '',
                      ),
                    ),
                  ),
                ),
              ),
              // 回车键
              IconButton(
                onPressed: _submit,
                icon: const Icon(Icons.keyboard_return_rounded,
                    size: 19, color: _accent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletions() {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 5),
        itemCount: _completions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final c = _completions[i];
          return GestureDetector(
            onTap: () => _applyCompletion(c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: _accent,
                    ),
                  ),
                  if (c.description.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(
                      c.description,
                      style: const TextStyle(fontSize: 10, color: _dim),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _LineKind { command, output, error, hint }

class _Line {
  _Line(this.text, this.kind, {this.partial = false});

  String text;
  final _LineKind kind;
  bool partial;
}

class _HistoryIntent extends Intent {
  const _HistoryIntent(this.delta);
  final int delta;
}

class _CompleteIntent extends Intent {
  const _CompleteIntent();
}
