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
      final proc = _isRoot
          ? await Process.start('su', ['-c', 'sh'], workingDirectory: _cwd)
          : await Process.start('sh', [], workingDirectory: _cwd);

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

    _input.clear();
    setState(() => _completions = const []);
    _history.add(cmd);
    _historyIndex = -1;

    // 回显：提示行 + 命令
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
        _cwd = target.startsWith('/') ? target : '$_cwd/$target';
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

  /// 提示串：`~/路径 $ `（根目录时显示 /）
  String _promptText() {
    final home = '/storage/emulated/0';
    final shown = _cwd == home
        ? '~'
        : (_cwd.startsWith('$home/') ? '~${_cwd.substring(home.length)}' : _cwd);
    return '$shown \$ ';
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
        if (_completions.isNotEmpty) {
          _applyCompletion(_completions.first);
        } else {
          // 没有候选时把 Tab 发给终端（shell 里可能有用）
          _onSend('\t');
        }
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
    return Scaffold(
      backgroundColor: _bg,
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
            return Text(
              line.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['monospace'],
                fontSize: 12.5,
                height: 1.35,
                color: switch (line.kind) {
                  _LineKind.command => _accent,
                  _LineKind.error => _err,
                  _LineKind.hint => _dim,
                  _LineKind.output => _fg,
                },
              ),
            );
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
                      // newline 而非 send：send 会让系统认为「完成」而收起键盘
                      textInputAction: TextInputAction.newline,
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
