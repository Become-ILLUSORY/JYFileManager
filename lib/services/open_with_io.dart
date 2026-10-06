// 原生平台：交给系统处理
import 'package:open_filex/open_filex.dart';

/// 打开文件，返回 null 表示成功，否则返回错误信息
Future<String?> openWithSystem(String path) async {
  final result = await OpenFilex.open(path);
  if (result.type == ResultType.done) return null;
  return result.message.isEmpty ? '系统没有可打开该类型文件的应用' : result.message;
}
