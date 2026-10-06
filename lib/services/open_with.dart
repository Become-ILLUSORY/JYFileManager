// 用系统关联程序打开文件：按平台选择实现
export 'open_with_io.dart' if (dart.library.js_interop) 'open_with_web.dart';
