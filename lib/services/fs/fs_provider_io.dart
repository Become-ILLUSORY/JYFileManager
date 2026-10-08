// 原生平台的文件系统入口
import 'mount_aware_fs.dart';
import 'vfs.dart';

/// 当前平台使用的文件系统实现。
///
/// 返回 [MountAwareFs]：在 SmartFs（含提权回退）之上再包一层挂载分发 ——
/// `/__mount__/...` 前缀的路径会被送到压缩包 / 远程客户端，
/// 其余路径原样交给 SmartFs。这样面板既能浏览挂载内容，
/// 又能保持「常规失败自动回退 Root/Shizuku」的能力。
Vfs get appFs => MountAwareFs.instance;
