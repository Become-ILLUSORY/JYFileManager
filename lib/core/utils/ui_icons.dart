// 界面图标：优先使用 Miuix OS4 矢量图标（随主题着色），缺失时回退 Material
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 界面动作图标集合。
///
/// Miuix 矢量图标通过 [MiuixIcon] 渲染，能跟随主题色着色；
/// OS4 集合没有的图标回退到 Material 图标，保证语义完整。
class UiIcons {
  UiIcons._();

  static MiuixVectorIcon? _n(String name) => MiuixIcons.os4.byName(name);

  // ===== OS4 矢量图标 =====
  static final menu = _n('menu');
  static final sidebar = _n('sidebar');
  static final more = _n('more');
  static final back = _n('back');
  static final forward = _n('forward');
  static final folder = _n('folder');
  static final file = _n('file');
  static final add = _n('add');
  static final create = _n('create');
  static final delete = _n('delete');
  static final copy = _n('copy');
  static final cut = _n('cut');
  static final paste = _n('paste');
  static final rename = _n('rename');
  static final share = _n('share');
  static final info = _n('info');
  static final settings = _n('settings');
  static final search = _n('search');
  static final refresh = _n('refresh');
  static final sort = _n('sort');
  static final close = _n('close');
  static final edit = _n('edit');
  static final image = _n('image');
  static final music = _n('music');
  static final movie = _n('movie');
  static final notes = _n('notes');
  static final lock = _n('lock');
  static final unlock = _n('unlock');
  static final link = _n('link');
  static final download = _n('download');
  static final save = _n('save');
  static final scan = _n('scan');
  static final tune = _n('tune');
  static final favorites = _n('favorites');
  static final starred = _n('starred');
  static final recent = _n('recent');
  static final all = _n('all');
  static final layers = _n('layers');
  static final filter = _n('filter');
  static final location = _n('location');
  static final store = _n('store');
  static final replace = _n('replace');
  static final theme = _n('theme');
  static final sync = _n('refresh');
  static final merge = _n('merge');
  static final remove = _n('remove');
  static final bookmark = _n('bookmark') ?? Icons.bookmark_rounded;
  static final book = _n('book');
  static final photos = _n('photos');
  static final play = _n('play');
  static final rocket = _n('rocket');
  static final tasks = _n('tasks');
  static final hide = _n('hide');
  static final show = _n('show');
  static final unpin = _n('unpin');
  static final unstar = _n('unstar');
  static final notifications = _n('notifications');
  static final background = _n('background');
  static final backup = _n('backup');
  static final import = _n('import');

  // ===== Material 回退（OS4 无对应图标）=====
  static const up = Icons.arrow_upward_rounded;
  static const home = Icons.home_rounded;
  static const storage = Icons.sd_storage_rounded;
  static const phone = Icons.smartphone_rounded;
  static const chevronRight = Icons.chevron_right_rounded;
  static const arrowUp = Icons.arrow_upward_rounded;
  static const archive = Icons.inventory_2_rounded;
  static const selectAll = Icons.select_all_rounded;
  static const gridView = Icons.grid_view_rounded;
  static const listView = Icons.view_list_rounded;
  static const addFolder = Icons.create_new_folder_rounded;
  static const addFile = Icons.note_add_rounded;
  static const textFile = Icons.description_rounded;
  static const terminal = Icons.terminal_rounded;
  static const lockOpen = Icons.lock_open_rounded;
  static const checkCircle = Icons.check_circle_rounded;
  static const radioOff = Icons.radio_button_unchecked;
  static const check = Icons.check_rounded;
  static const error = Icons.error_outline_rounded;
  static const language = Icons.translate_rounded;
  static const wrapText = Icons.wrap_text_rounded;
  static const undo = Icons.undo_rounded;
  static const redo = Icons.redo_rounded;
  static const findReplace = Icons.find_replace_rounded;
  static const code = Icons.code_rounded;
  static const fontSize = Icons.format_size_rounded;
}

/// 渲染一个界面图标：优先矢量图标，否则用 Material 图标。
Widget uiIcon(
  dynamic icon, {
  double size = 22,
  Color? color,
}) {
  if (icon is MiuixVectorIcon) {
    return MiuixIcon(vector: icon, size: size, tint: color);
  }
  return Icon(icon as IconData, size: size, color: color);
}
