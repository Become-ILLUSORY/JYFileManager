// 文本编辑器：直接打开并编辑常见文本/代码文件。
//
// 为什么需要它：手机上往往没有能打开 .txt / .yaml / .py 的应用，
// 交给系统「打开方式」会直接失败。内置编辑器保证这类文件点开就能看、能改。
//
// 关键设计：
//   - 语法高亮：自定义 TextEditingController 覆写 buildTextSpan，
//     这样光标、选区、滚动、输入法全部保持原生行为（TextField 本身
//     不支持富文本，只有走 controller 这条路才是对的）
//   - 编码：自动检测 UTF-8 / UTF-16 / GBK / Big5，状态栏显示并可手动切换
//     （中文文本用 GBK 保存的场景很常见，乱码时要能纠正）
//   - 换行：统一按 \n 编辑，保存时保留原文件的换行风格（CRLF/LF）
//   - 大文件：超过阈值时只读预览，避免整篇重排卡顿
//   - 未保存改动：返回/关闭时二次确认
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/utils/text_codec.dart';
import '../../core/utils/text_file_kinds.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/app_settings.dart';
import '../../services/fs/fs_provider.dart';
import '../widgets/code_highlighter.dart';
import '../widgets/code_theme.dart';

/// 超过这个大小就只读预览（编辑会因整篇重排而卡顿）
const int kEditorReadOnlyLimit = 2 * 1024 * 1024;

/// 超过这个大小就不做语法高亮（纯文本显示）
const int kEditorHighlightLimit = 512 * 1024;

/// 字号范围（双指缩放用）
const double kEditorMinFontSize = 8;
const double kEditorMaxFontSize = 32;

/// 大文件阈值：超过后进入「流畅模式」——
/// 不做语法高亮、行高更紧凑，保证滚动不掉帧。
const int kEditorSmoothLimit = 256 * 1024;

/// 打开文本编辑器
Future<void> showTextEditor(
  BuildContext context, {
  required String path,
  required String name,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TextEditorPage(path: path, name: name),
      fullscreenDialog: true,
    ),
  );
}

/// 带语法高亮的文本控制器。
///
/// 覆写 buildTextSpan 是 Flutter 里给 TextField 加高亮的标准做法：
/// 输入、选区、光标、输入法组合全部由框架照常处理，只有绘制样式被替换。
class _HighlightController extends TextEditingController {
  _HighlightController({
    required this.language,
    required this.theme,
    required this.baseStyle,
    required this.enabled,
  });

  String? language;
  Map<String, TextStyle> theme;
  TextStyle baseStyle;
  bool enabled;

  /// 高亮结果缓存：内容与参数不变时直接复用，避免每帧重新解析
  String? _cacheKey;
  TextSpan? _cacheSpan;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    // 大文件直接返回纯文本：避免每次重绘都跑一遍高亮解析，
    // 这是大文件卡顿的主要来源。
    if (!enabled || text.length > kEditorHighlightLimit) {
      return TextSpan(text: text, style: style ?? baseStyle);
    }

    final key = '$language|${theme.length}|${identityHashCode(theme)}'
        '|${style?.fontSize}|${text.length}|${text.hashCode}';
    if (_cacheKey == key && _cacheSpan != null) return _cacheSpan!;

    final span = CodeHighlighter.render(
      text,
      language: language,
      base: style ?? baseStyle,
      theme: theme,
    );
    _cacheKey = key;
    _cacheSpan = span;
    return span;
  }
}

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  late final _HighlightController _controller = _HighlightController(
    language: _kind?.language,
    theme: CodeThemes.light,
    baseStyle: const TextStyle(),
    enabled: true,
  );
  final _focusNode = FocusNode();

  final _fs = appFs;
  final _settings = AppSettings.instance;

  bool _loading = true;
  String? _error;

  /// 原始字节与检测到的编码
  Uint8List _bytes = Uint8List(0);
  TextEncoding _encoding = TextEncoding.utf8;

  /// 原文件是否用 CRLF 换行（保存时保持一致）
  bool _crlf = false;

  /// 加载时的原始文本，用于判断是否有改动
  String _original = '';

  /// 大文件只读
  bool _readOnly = false;

  bool _saving = false;

  /// 当前字号（可双指缩放，会持久化到设置）
  late double _fontSize = _settings.editorFontSize;

  /// 是否自动换行
  late bool _wrap = _settings.editorWrap;

  /// 缩放起始字号
  double _scaleStartFontSize = 14;

  /// 大文件「流畅模式」：不做语法高亮，滚动更顺
  bool _smooth = false;

  /// 加载中的提示文字（大文件用）
  String? _loadingHint;

  TextKind? get _kind => TextFileKinds.kindOf(widget.name);
  String get _typeLabel => _kind?.label ?? '文本文件';

  bool get _dirty => !_readOnly && _controller.text != _original;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // 只更新状态栏（字数/未保存标记），不重建编辑区
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 先取文件大小：大文件时给出明确的加载提示，
      // 避免用户以为卡死（读取 + 解码 + 首次布局都要时间）
      int size = 0;
      try {
        size = await _fs.length(widget.path);
      } catch (_) {}

      if (mounted && size > kEditorSmoothLimit) {
        setState(() => _loadingHint = '正在加载 ${(size / 1024 / 1024).toStringAsFixed(1)} MB…');
      }

      final bytes = await _fs.readBytes(widget.path);
      final detection = TextCodecUtil.detect(bytes);
      var text = TextCodecUtil.decode(bytes, detection.encoding);
      final crlf = text.contains('\r\n');
      text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _encoding = detection.encoding;
        _crlf = crlf;
        _original = text;
        _readOnly = bytes.length > kEditorReadOnlyLimit;
        // 大文件进入流畅模式：不做语法高亮，保证滚动顺滑
        _smooth = bytes.length > kEditorSmoothLimit;
        _controller.enabled = !_smooth;
        _controller.text = text;
        _loading = false;
        _loadingHint = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_readOnly || _saving) return;
    setState(() => _saving = true);
    try {
      var text = _controller.text;
      if (_crlf) text = text.replaceAll('\n', '\r\n');
      final bytes = TextCodecUtil.encode(text, _encoding);
      await _fs.writeBytes(widget.path, bytes);
      if (!mounted) return;
      setState(() {
        _original = _controller.text;
        _saving = false;
      });
      _snack('已保存');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('保存失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  /// 切换编码并重新解码（中文乱码时手动纠正）
  Future<void> _switchEncoding() async {
    final colors = MiuixTheme.of(context).colors;
    final picked = await showModalBottomSheet<TextEncoding>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Row(
                    children: [
                      Text(
                        '选择编码',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final e in TextEncoding.values)
                  InkWell(
                    onTap: () => Navigator.of(ctx).pop(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.label,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          if (e == _encoding)
                            uiIcon(UiIcons.check,
                                size: 18, color: colors.primary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || picked == _encoding) return;

    final text = TextCodecUtil.decode(_bytes, picked)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    setState(() {
      _encoding = picked;
      _original = text;
      _controller.text = text;
    });
    _snack('已切换为 ${picked.label}');
  }

  /// 返回前确认未保存改动
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: Text('「${widget.name}」有未保存的修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              _save();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final dark = theme.brightness == Brightness.dark;

    // 高亮主题随明暗切换
    _controller
      ..theme = CodeThemes.of(dark)
      ..enabled = !_readOnly;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: MiuixScaffold(
        containerColor: colors.background,
        topBar: _buildTopBar(colors),
        content: (padding) => Padding(
          padding: EdgeInsets.only(top: padding.top),
          child: _buildBody(colors),
        ),
      ),
    );
  }

  Widget _buildTopBar(MiuixColors colors) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: () async {
                if (await _confirmDiscard() && mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: uiIcon(UiIcons.back, size: 22, color: colors.onSurface),
                          ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            if (!_readOnly)
              IconButton(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : uiIcon(
                        UiIcons.save,
                        size: 21,
                        color: _dirty ? colors.primary : colors.onSurface,
                      ),
                              ),
            IconButton(
              onPressed: _switchEncoding,
              icon:
                  uiIcon(UiIcons.language, size: 21, color: colors.onSurface),
            ),
            // 自动换行开关
            IconButton(
              onPressed: () {
                setState(() => _wrap = !_wrap);
                _settings.setEditorWrap(_wrap);
              },
              icon: uiIcon(
                UiIcons.wrapText,
                size: 21,
                color: _wrap ? colors.primary : colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[_typeLabel, _encoding.label];
    if (_readOnly) parts.add('只读（文件过大）');
    if (_smooth && !_readOnly) parts.add('流畅模式');
    if (_dirty) parts.add('未保存');
    if (_bytes.isNotEmpty) {
      final kb = _bytes.length / 1024;
      parts.add(kb >= 1024
          ? '${(kb / 1024).toStringAsFixed(1)} MB'
          : '${kb.toStringAsFixed(1)} KB');
    }
    return parts.join(' · ');
  }

  Widget _buildBody(MiuixColors colors) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colors.primary),
            if (_loadingHint != null) ...[
              const SizedBox(height: 14),
              Text(
                _loadingHint!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              uiIcon(UiIcons.error, size: 40, color: colors.error),
              const SizedBox(height: 14),
              Text(
                '打开失败',
                style: TextStyle(fontSize: 16, color: colors.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
              const SizedBox(height: 18),
              MiuixButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final base = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['monospace', 'Roboto Mono', 'Courier New'],
      fontSize: _fontSize,
      height: 1.5,
      color: colors.onSurface,
    );

    return Container(
      color: colors.background,
      // 双指缩放：用 onScaleUpdate 而不是 InteractiveViewer ——
      // 后者会抢走单指的滚动与光标拖拽，编辑体验会坏掉。
      // 这里只在检测到「两指以上」时才调整字号。
      child: GestureDetector(
        onScaleStart: (d) {
          _scaleStartFontSize = _fontSize;
        },
        onScaleUpdate: (d) {
          if (d.pointerCount < 2) return; // 单指留给滚动/选字
          final next = (_scaleStartFontSize * d.scale)
              .clamp(kEditorMinFontSize, kEditorMaxFontSize);
          if ((next - _fontSize).abs() < 0.5) return;
          setState(() => _fontSize = next);
        },
        onScaleEnd: (_) {
          // 缩放结束后持久化字号，下次打开还是这个大小
          _settings.setEditorFontSize(_fontSize);
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          readOnly: _readOnly,
          // 自动换行开：长行折行显示（maxLines: null）
          // 自动换行关：保持单行 + 横向滚动，长行不折
          maxLines: _wrap ? null : 1,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: base,
          cursorColor: colors.primary,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          // 关掉自动纠错/首字母大写，否则编辑代码会被系统改字
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.fromLTRB(14, 12, 14, 80),
          ),
        ),
      ),
    );
  }
}
