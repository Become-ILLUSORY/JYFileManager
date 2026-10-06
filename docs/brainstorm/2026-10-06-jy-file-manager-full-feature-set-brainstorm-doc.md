---
date: 2026-10-06
topic: jy-file-manager-full-feature-set
---

# JY文件管理器 — 全功能实现方向

## What We're Building

一款 **Liquid Glass 设计语言的双面板文件管理器**（Android），参考业界成熟文件管理器的完整功能面（经官网手册调研：40+ 项功能），
以「双窗口操作」为核心交互，叠加文件编辑（文本/Hex/对比）、压缩包处理（zip/7z/rar/tar 系）、
APK 工具箱（信息/Manifest/DEX/ARSC/签名）与系统工具（终端/应用提取/远程管理）。

技术基线：Flutter 3.47.6 + flutter_miuix 1.3.0（HyperOS 组件），代码在本地沙箱编写、GitHub Actions 云端编译出 APK。

## Why This Approach

| 方案 | 说明 | 结论 |
|------|------|------|
| A. 纯 Material 3 自绘 | 完全自由但工作量大，失去 HyperOS 原生质感 | 否 |
| B. flutter_miuix + Liquid Glass 玻璃层 | 组件成熟（45+ 组件、OS4 玻璃材质、Monet 取色），双面板用玻璃工具栏区分层级 | ✅ 采用 |
| C. 原生 Android 重写 | 性能最好但无法用 Flutter 生态，开发速度慢 | 否 |

选 B：组件库覆盖顶栏/导航/弹窗/模糊全套 API，且支持「玻璃开关」按需降级为普通样式，符合"有的用户不喜欢玻璃"的诉求。

## Key Decisions

- **双面板布局**：左右两个独立文件面板 + 中央分隔条；顶栏/底栏用 Liquid Glass 材质悬浮，内容区正常渲染（用户指定）
- **玻璃开关**：`AppSettings.glassEnabled` 全局开关，关闭时顶栏/底栏降级为纯色 MIUIx 样式（用户指定）
- **品牌独立**：以 JY文件管理器 独立命名，突出自有设计语言（用户指定）
- **本地写码 + Actions 编译**：本地沙箱 flutter analyze 保证零错误，GitHub Actions (x64) 产出签名 APK（用户指定）
- **工作流**：VGV Wingspan 四阶段（Brainstorm → Plan → Build → Review），分里程碑推进（用户指定）
- **自研引擎**（无现成 Dart 包的部分）：AXML 编解码、ARSC 解析、DEX 解析、APK v1/v2/v3 签名、WebDAV 客户端、文本对比引擎
- **功能分级**：全部 40+ 功能列入计划表，按 M0→M5 六个里程碑推进；「应用保护」类服务端功能不实现（原品已停售）
- **签名密钥**：复用既有自签密钥体系（RSA2048/SHA256，30 年），Actions 注入 secrets

## Open Questions

- 里程碑优先级：默认按「核心体验 → 编辑能力 → 逆向工具 → 系统工具」推进，可调整
- 7z/rar 解压：archive 包对 7z 支持有限，必要时捆绑 7-Zip 二进制（LGPL）或降级为 zip/tar 系
- DEX 编辑的 Smali 反编译规模大：先做「浏览 + 搜索」，编辑（保存回 DEX）放后期
- MCP 服务：作为收官功能，接口协议对齐 MCP 规范

## 调研存档

- 功能调研笔记：`docs/research-notes/`（35 页，含快速入门/文件管理/逆向/实战）
- 功能矩阵：`docs/FEATURES.md`
- Wingspan 规范：`docs/wingspan/`
