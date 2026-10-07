// 终端模拟器：在本机 shell 里执行命令并显示输出。
//
// 实现方式：直接调用系统 sh（Process.start），支持交互式命令的
// 标准输入输出流。Root 已就绪时可以用 su 执行特权命令。
//
// 说明：Android 应用进程能执行的都是该应用权限范围内的命令；
// 访问 /data 等受限位置需要 Root/Shizuku（提权就绪时自动走 su）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../services/privilege.dart';

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

  /// 历史命令（上下键翻阅）
  final _history = <String>[];
  int _historyIndex = -1;

  bool _running = false;
  String _cwd = '/';

  @override
  void initState() {
    super.initState();
    _cwd = Directory.current.path;
    _print('JY 终端 — 输入命令后回车执行，exit 退出', _LineKind.hint);
    _print('当前用户：${_isRoot ? "root" : "应用权限"}', _LineKind.hint);
    _print('', _LineKind.output);
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

  Future<void> _startShell() async {
    try {
      // 有 Root 时用 su 启动 shell，否则用普通 sh
      final proc = _isRoot
          ? await Process.start('su', ['-c', 'sh'], workingDirectory: _cwd)
          : await Process.start('sh', [], workingDirectory: _cwd);

      _process = proc;
      _stdin = proc.stdin;
      setState(() => _running = true);

      // 输出流：按行追加
      proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) => _append(chunk, _LineKind.output));
      proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) => _append(chunk, _LineKind.error));

      proc.exitCode.then((code) {
        if (!mounted) return;
        setState(() => _running = false);
        _print('[进程已退出，代码 $code]', _LineKind.hint);
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

  /// 追加流式输出（可能不含换行，需要续在上一行后面）
  void _append(String chunk, _LineKind kind) {
    if (chunk.isEmpty) return;
    setState(() {
      if (_output.isNotEmpty && _output.last.partial) {
        _output.last.text += chunk;
      } else {
        _output.add(_Line(chunk, kind, partial: true));
      }
      // 收到换行就认为这一段结束
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

  Future<void> _submit() async {
    final cmd = _input.text.trim();
    if (cmd.isEmpty) return;
    _input.clear();

    _history.add(cmd);
    _historyIndex = -1;

    _print('\$ $cmd', _LineKind.command);

    // 内置命令
    if (cmd == 'clear') {
      setState(() => _output.clear());
      return;
    }
    if (cmd == 'exit') {
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
      // 记录 cd 以同步工作目录显示
      if (cmd == 'cd' || cmd.startsWith('cd ')) {
        final target = cmd == 'cd' ? '/' : cmd.substring(3).trim();
        _cwd = target.startsWith('/') ? target : '$_cwd/$target';
      }
      stdin.writeln(cmd);
      await stdin.flush();
    } catch (e) {
      _print('执行失败：$e', _LineKind.error);
    }
  }

  void _useHistory(int delta) {
    if (_history.isEmpty) return;
    var idx = _historyIndex + delta;
    if (idx < 0) idx = 0;
    if (idx >= _history.length) {
      idx = _history.length - 1;
    }
    _historyIndex = idx;
    _input.text = _history[idx];
    _input.selection =
        TextSelection.collapsed(offset: _input.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final dark = theme.brightness == Brightness.dark;

    // 终端配色：浅色下用深色终端（更接近真实终端观感）
    final bg = dark ? const Color(0xFF14161A) : const Color(0xFF1E2228);
    final fg = const Color(0xFFD8DEE9);
    final accent = const Color(0xFF7FD1FF);

    return MiuixScaffold(
      containerColor: bg,
      topBar: _buildTopBar(colors),
      content: (padding) => Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _inputFocus.requestFocus(),
                child: Container(
                  width: double.infinity,
                  color: bg,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: _output.length,
                    itemBuilder: (ctx, i) {
                      final line = _output[i];
                      return Text(
                        line.text,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['monospace'],
                          fontSize: 12,
                          height: 1.4,
                          color: switch (line.kind) {
                            _LineKind.command => accent,
                            _LineKind.error => const Color(0xFFFF8A80),
                            _LineKind.hint =>
                              const Color(0xFF8B949E),
                            _LineKind.output => fg,
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            _buildInputBar(bg, fg, accent),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(MiuixColors colors) {
    return Container(
      color: const Color(0xFF23272E),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded,
                  size: 22, color: Color(0xFFD8DEE9)),
            ),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '终端模拟器',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD8DEE9),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'sh',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '清屏',
              onPressed: () => setState(() => _output.clear()),
              icon: const Icon(Icons.cleaning_services_rounded,
                  size: 20, color: Color(0xFFD8DEE9)),
            ),
            IconButton(
              tooltip: '重启 shell',
              onPressed: () {
                _process?.kill();
                _output.clear();
                _print('shell 已重启', _LineKind.hint);
                _startShell();
              },
              icon: const Icon(Icons.refresh_rounded,
                  size: 20, color: Color(0xFFD8DEE9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(Color bg, Color fg, Color accent) {
    return Container(
      color: const Color(0xFF23272E),
      padding: EdgeInsets.only(
        left: 12,
        right: 6,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
      ),
      child: Row(
        children: [
          Text(
            '\$',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    _HistoryIntent(-1),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    _HistoryIntent(1),
              },
              child: Actions(
                actions: {
                  _HistoryIntent: CallbackAction<_HistoryIntent>(
                    onInvoke: (intent) {
                      _useHistory(intent.delta);
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  autofocus: true,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: fg,
                  ),
                  cursorColor: accent,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: '输入命令…',
                    hintStyle: TextStyle(
                      color: Color(0xFF6E7681),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _submit,
            icon: Icon(Icons.keyboard_return_rounded, size: 20, color: accent),
          ),
        ],
      ),
    );
  }
}

enum _LineKind { command, output, error, hint }

class _Line {
  _Line(this.text, this.kind, {this.partial = false});

  String text;
  final _LineKind kind;

  /// 是否为「未收到换行的流式片段」
  bool partial;
}

class _HistoryIntent extends Intent {
  const _HistoryIntent(this.delta);
  final int delta;
}
