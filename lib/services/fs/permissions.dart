// 存储权限入口：按平台选择实现
//
// 原生平台走 permission_handler；Web 预览下无需权限，直接放行。
export 'permissions_io.dart'
    if (dart.library.js_interop) 'permissions_web.dart';
