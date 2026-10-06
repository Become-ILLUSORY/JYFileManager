# JY文件管理器

**Liquid Glass 风格的双面板文件管理器** — Flutter + HyperOS 设计语言

## ✨ 特性

- **双面板操作**：左右两个独立目录视图，前进/后退/同步，跨面板复制移动更高效
- **Liquid Glass 设计**：基于 HyperOS / MIUIx 设计语言的玻璃材质界面，可在设置中一键关闭
- **文件管理**：多选、排序、过滤、书签、批量重命名、属性查看
- **文本/Hex 编辑器**：多编码支持（UTF-8/GBK/Big5 等）、语法高亮、字节级编辑
- **压缩包**：zip/tar/7z 浏览与解压、APK 直接进入查看
- **APK 工具箱**：信息解析、DEX/ARSC/AXML 查看、签名校验与重签
- **远程管理**：FTP / WebDAV 客户端与服务器
- **ROOT 支持**：可选 Root 模式访问系统分区

## 🛠 技术栈

- Flutter 3.47 · Dart 3.13
- [flutter_miuix](https://pub.dev/packages/flutter_miuix) — HyperOS 风格组件库（含 OS4 玻璃材质）
- provider 状态管理

## 📦 构建

推送代码后 GitHub Actions 自动构建 APK（见 `.github/workflows/build.yml`）：

- `main` 分支推送 → 构建并上传 artifact
- 打 tag `v*` → 自动创建 Release

本地构建：

```bash
flutter pub get
flutter build apk --release
```

## 📄 开发文档

- [功能规划](docs/FEATURES.md)
- [设计决策](docs/brainstorm/)
- [实施计划](docs/plan/)

## 📃 License

MIT
