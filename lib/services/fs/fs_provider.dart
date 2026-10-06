// 文件系统入口：按平台选择实现
//
// - Android/桌面：本地文件系统（dart:io）
// - Web（预览/演示）：内存演示文件系统
//
// UI 层只依赖 [appFs]，因此同一套界面可在浏览器里预览与迭代。
export 'fs_provider_io.dart' if (dart.library.js_interop) 'fs_provider_web.dart';
