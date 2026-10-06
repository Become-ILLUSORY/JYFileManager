// 原生平台的文件系统入口
import 'local_fs.dart';
import 'vfs.dart';

/// 当前平台使用的文件系统实现
Vfs get appFs => LocalFs.instance;
