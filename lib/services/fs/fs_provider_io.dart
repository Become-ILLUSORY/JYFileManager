// 原生平台的文件系统入口
import 'smart_fs.dart';
import 'vfs.dart';

/// 当前平台使用的文件系统实现。
///
/// 返回 [SmartFs]：常规访问失败且用户已开启提权时，
/// 会自动回退到 Root / Shizuku 通道。
Vfs get appFs => SmartFs.instance;
