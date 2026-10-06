// 应用设置：持久化用户偏好
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/bookmark.dart';

/// 主题模式
enum AppThemeMode { system, light, dark }

/// 应用设置模型（单例 + ChangeNotifier）
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kThemeMode = 'theme_mode';
  static const _kMonet = 'monet_enabled';
  static const _kKeyColor = 'key_color';
  static const _kShowHidden = 'show_hidden';
  static const _kFoldersFirst = 'folders_first';
  static const _kDualPanel = 'dual_panel';
  static const _kEditorFontSize = 'editor_font_size';
  static const _kEditorWrap = 'editor_wrap';
  static const _kBookmarks = 'bookmarks';
  static const _kLeftPath = 'left_path';
  static const _kRightPath = 'right_path';
  static const _kGlassEnabled = 'glass_enabled';
  static const _kDefaultEncoding = 'default_encoding';

  SharedPreferences? _prefs;

  AppThemeMode _themeMode = AppThemeMode.system;
  bool _monetEnabled = false;
  int _keyColorValue = 0xFF4C662B;
  bool _showHidden = true;
  bool _foldersFirst = true;
  bool _dualPanel = true;
  double _editorFontSize = 14;
  bool _editorWrap = true;
  String _leftPath = '/storage/emulated/0';
  String _rightPath = '/storage/emulated/0';
  bool _glassEnabled = true;
  String _defaultEncoding = 'UTF-8';

  AppThemeMode get themeMode => _themeMode;
  bool get monetEnabled => _monetEnabled;
  Color get keyColor => Color(_keyColorValue);
  bool get showHidden => _showHidden;
  bool get foldersFirst => _foldersFirst;
  bool get dualPanel => _dualPanel;
  double get editorFontSize => _editorFontSize;
  bool get editorWrap => _editorWrap;
  String get leftPath => _leftPath;
  String get rightPath => _rightPath;
  bool get glassEnabled => _glassEnabled;
  String get defaultEncoding => _defaultEncoding;

  ThemeMode get materialThemeMode => switch (_themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    _themeMode = AppThemeMode.values[
        p.getInt(_kThemeMode) ?? AppThemeMode.system.index];
    _monetEnabled = p.getBool(_kMonet) ?? false;
    _keyColorValue = p.getInt(_kKeyColor) ?? 0xFF4C662B;
    _showHidden = p.getBool(_kShowHidden) ?? true;
    _foldersFirst = p.getBool(_kFoldersFirst) ?? true;
    _dualPanel = p.getBool(_kDualPanel) ?? true;
    _editorFontSize = p.getDouble(_kEditorFontSize) ?? 14;
    _editorWrap = p.getBool(_kEditorWrap) ?? true;
    _leftPath = p.getString(_kLeftPath) ?? '/storage/emulated/0';
    _rightPath = p.getString(_kRightPath) ?? '/storage/emulated/0';
    _glassEnabled = p.getBool(_kGlassEnabled) ?? true;
    _defaultEncoding = p.getString(_kDefaultEncoding) ?? 'UTF-8';
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) {
    _themeMode = mode;
    _prefs?.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  void setMonet(bool value) {
    _monetEnabled = value;
    _prefs?.setBool(_kMonet, value);
    notifyListeners();
  }

  void setKeyColor(Color color) {
    _keyColorValue = color.toARGB32();
    _prefs?.setInt(_kKeyColor, _keyColorValue);
    notifyListeners();
  }

  void setShowHidden(bool value) {
    _showHidden = value;
    _prefs?.setBool(_kShowHidden, value);
    notifyListeners();
  }

  void setFoldersFirst(bool value) {
    _foldersFirst = value;
    _prefs?.setBool(_kFoldersFirst, value);
    notifyListeners();
  }

  void setDualPanel(bool value) {
    _dualPanel = value;
    _prefs?.setBool(_kDualPanel, value);
    notifyListeners();
  }

  void setEditorFontSize(double value) {
    _editorFontSize = value;
    _prefs?.setDouble(_kEditorFontSize, value);
    notifyListeners();
  }

  void setEditorWrap(bool value) {
    _editorWrap = value;
    _prefs?.setBool(_kEditorWrap, value);
    notifyListeners();
  }

  void saveLeftPath(String path) {
    _leftPath = path;
    _prefs?.setString(_kLeftPath, path);
  }

  void saveRightPath(String path) {
    _rightPath = path;
    _prefs?.setString(_kRightPath, path);
  }

  void setGlassEnabled(bool value) {
    _glassEnabled = value;
    _prefs?.setBool(_kGlassEnabled, value);
    notifyListeners();
  }

  void setDefaultEncoding(String value) {
    _defaultEncoding = value;
    _prefs?.setString(_kDefaultEncoding, value);
    notifyListeners();
  }

  String? getString(String key) => _prefs?.getString(key);
  Future<void> setString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  /// 读取用户书签（JSON 数组字符串）
  List<Bookmark> loadBookmarks() {
    final raw = _prefs?.getString(_kBookmarks);
    if (raw == null || raw.isEmpty) return BookmarkStore.builtin;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final items = list
          .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
          .toList();
      return items.isEmpty ? BookmarkStore.builtin : items;
    } catch (_) {
      return BookmarkStore.builtin;
    }
  }

  /// 保存书签
  Future<void> saveBookmarks(List<Bookmark> items) async {
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs?.setString(_kBookmarks, raw);
    notifyListeners();
  }
}
