// Web 平台的文件系统入口（使用内存演示文件系统，便于界面预览）
import 'demo_fs.dart';
import 'vfs.dart';

/// 当前平台使用的文件系统实现
Vfs get appFs => DemoFs.instance;
