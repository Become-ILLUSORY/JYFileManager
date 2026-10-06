// 图标映射：根据文件类型选择图标
import 'package:flutter/material.dart';

/// 文件图标描述
class FileIconInfo {
  final IconData icon;
  final Color? color;
  const FileIconInfo(this.icon, [this.color]);
}

/// 根据扩展名返回图标信息。
///
/// 颜色参数说明：
/// - 文件夹使用主题色（由调用方处理，这里返回 null 表示用默认）
/// - 特殊格式使用固定色，与业界通用配色一致
FileIconInfo iconForExtension(String ext, {bool isDirectory = false}) {
  if (isDirectory) return const FileIconInfo(Icons.folder_rounded);

  switch (ext) {
    // ===== 图片 =====
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'heic':
    case 'heif':
    case 'avif':
    case 'ico':
    case 'tiff':
    case 'tif':
      return const FileIconInfo(Icons.image_rounded, Color(0xFF4CAF50));
    case 'svg':
      return const FileIconInfo(Icons.polyline_rounded, Color(0xFF8BC34A));

    // ===== 视频 =====
    case 'mp4':
    case 'mkv':
    case 'avi':
    case 'mov':
    case 'wmv':
    case 'flv':
    case 'webm':
    case '3gp':
    case 'm4v':
    case 'rmvb':
    case 'rm':
    case 'ts':
      return const FileIconInfo(Icons.movie_rounded, Color(0xFFE91E63));

    // ===== 音频 =====
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'aac':
    case 'ogg':
    case 'm4a':
    case 'wma':
    case 'opus':
    case 'ape':
    case 'amr':
      return const FileIconInfo(Icons.music_note_rounded, Color(0xFF9C27B0));

    // ===== 压缩包 =====
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
    case 'tgz':
    case 'bz2':
    case 'xz':
    case 'zst':
    case 'lz4':
    case 'cab':
    case 'iso':
      return const FileIconInfo(Icons.folder_zip_rounded, Color(0xFFFF9800));

    // ===== APK / 安装包 =====
    case 'apk':
    case 'apks':
    case 'xapk':
    case 'apkm':
      return const FileIconInfo(Icons.android_rounded, Color(0xFF3DDC84));
    case 'ipa':
      return const FileIconInfo(Icons.apple_rounded, Color(0xFF999999));

    // ===== 代码 =====
    case 'dart':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF0175C2));
    case 'java':
    case 'kt':
    case 'kts':
    case 'groovy':
    case 'gradle':
    case 'class':
      return const FileIconInfo(Icons.coffee_rounded, Color(0xFFB07219));
    case 'c':
    case 'h':
    case 'cpp':
    case 'cc':
    case 'cxx':
    case 'hpp':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF555555));
    case 'py':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF3572A5));
    case 'js':
    case 'mjs':
    case 'cjs':
      return const FileIconInfo(Icons.javascript_rounded, Color(0xFFF1E05A));
    case 'tsx':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF3178C6));
    case 'jsx':
    case 'vue':
    case 'svelte':
      return const FileIconInfo(Icons.web_rounded, Color(0xFF41B883));
    case 'go':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF00ADD8));
    case 'rs':
      return const FileIconInfo(Icons.code_rounded, Color(0xFFDEA584));
    case 'swift':
      return const FileIconInfo(Icons.code_rounded, Color(0xFFF05138));
    case 'rb':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF701516));
    case 'php':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF4F5D95));
    case 'cs':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF178600));
    case 'lua':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF000080));
    case 'sh':
    case 'bash':
    case 'zsh':
    case 'fish':
      return const FileIconInfo(Icons.terminal_rounded, Color(0xFF89E051));
    case 'bat':
    case 'cmd':
    case 'ps1':
      return const FileIconInfo(Icons.terminal_rounded, Color(0xFFC1F12E));

    // ===== 标记语言 / 配置 =====
    case 'html':
    case 'htm':
    case 'xhtml':
      return const FileIconInfo(Icons.html_rounded, Color(0xFFE34C26));
    case 'css':
    case 'scss':
    case 'sass':
    case 'less':
      return const FileIconInfo(Icons.css_rounded, Color(0xFF563D7C));
    case 'json':
      return const FileIconInfo(Icons.data_object_rounded, Color(0xFFCBCB41));
    case 'xml':
    case 'plist':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF0060AC));
    case 'yaml':
    case 'yml':
      return const FileIconInfo(Icons.settings_suggest_rounded, Color(0xFFCB171E));
    case 'toml':
    case 'ini':
    case 'cfg':
    case 'conf':
    case 'properties':
    case 'prop':
      return const FileIconInfo(Icons.settings_rounded, Color(0xFF9E9E9E));
    case 'sql':
      return const FileIconInfo(Icons.storage_rounded, Color(0xFFE38C00));
    case 'md':
    case 'markdown':
    case 'rst':
      return const FileIconInfo(Icons.article_rounded, Color(0xFF519ABA));
    case 'txt':
    case 'text':
    case 'log':
    case 'diff':
    case 'patch':
      return const FileIconInfo(Icons.description_rounded, Color(0xFF9E9E9E));
    case 'csv':
    case 'tsv':
      return const FileIconInfo(Icons.table_chart_rounded, Color(0xFF217346));

    // ===== 文档 =====
    case 'pdf':
      return const FileIconInfo(Icons.picture_as_pdf_rounded, Color(0xFFE53935));
    case 'doc':
    case 'docx':
      return const FileIconInfo(Icons.description_rounded, Color(0xFF2B579A));
    case 'xls':
    case 'xlsx':
      return const FileIconInfo(Icons.table_chart_rounded, Color(0xFF217346));
    case 'ppt':
    case 'pptx':
      return const FileIconInfo(Icons.slideshow_rounded, Color(0xFFD24726));
    case 'epub':
    case 'mobi':
    case 'azw3':
      return const FileIconInfo(Icons.menu_book_rounded, Color(0xFF8BC34A));

    // ===== 字体 =====
    case 'ttf':
    case 'otf':
    case 'woff':
    case 'woff2':
      return const FileIconInfo(Icons.text_fields_rounded, Color(0xFF607D8B));

    // ===== 数据库 =====
    case 'db':
    case 'sqlite':
    case 'sqlite3':
      return const FileIconInfo(Icons.storage_rounded, Color(0xFF003B57));

    // ===== 二进制 / 系统 =====
    case 'so':
      return const FileIconInfo(Icons.memory_rounded, Color(0xFF795548));
    case 'dex':
    case 'odex':
    case 'vdex':
    case 'oat':
    case 'art':
      return const FileIconInfo(Icons.memory_rounded, Color(0xFF9C27B0));
    case 'jar':
      return const FileIconInfo(Icons.inventory_2_rounded, Color(0xFFFF9800));
    case 'exe':
    case 'dll':
    case 'bin':
    case 'img':
      return const FileIconInfo(Icons.settings_applications_rounded, Color(0xFF607D8B));
    case 'smali':
      return const FileIconInfo(Icons.code_rounded, Color(0xFF00BFA5));

    default:
      return const FileIconInfo(Icons.insert_drive_file_rounded);
  }
}

/// 根据文件项返回图标（考虑目录/链接）
FileIconInfo iconForFile({
  required String name,
  required bool isDirectory,
  required bool isLink,
}) {
  if (isLink) {
    final info = isDirectory
        ? const FileIconInfo(Icons.folder_rounded)
        : iconForExtension(_ext(name));
    return FileIconInfo(Icons.link_rounded, info.color);
  }
  if (isDirectory) return const FileIconInfo(Icons.folder_rounded);
  return iconForExtension(_ext(name));
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// 文件类型的中文描述（属性对话框用）
String fileTypeDescription(String name, {required bool isDirectory}) {
  if (isDirectory) return '文件夹';
  final ext = _ext(name);
  if (ext.isEmpty) return '文件';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
      return '图像文件 ($ext)';
    case 'mp4':
    case 'mkv':
    case 'avi':
    case 'mov':
      return '视频文件 ($ext)';
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'aac':
      return '音频文件 ($ext)';
    case 'zip':
    case 'rar':
    case '7z':
      return '压缩文件 ($ext)';
    case 'apk':
      return '安卓安装包';
    case 'txt':
    case 'md':
    case 'log':
      return '文本文件 ($ext)';
    case 'dex':
      return 'Dalvik 可执行文件';
    case 'so':
      return '共享库';
    case 'ttf':
    case 'otf':
      return '字体文件 ($ext)';
    default:
      return '$ext 文件';
  }
}
