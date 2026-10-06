---
title: JY文件管理器 全功能实现计划
type: feat
date: 2026-10-06
---

# JY文件管理器 全功能实现计划

## Overview

按里程碑 M0→M6 推进全部 40+ 项功能（调研自业界成熟产品官网手册，见 `docs/FEATURES.md`）。
每个里程碑是一个独立可交付阶段，完成后 CI 产出可安装 APK。工作流：Brainstorm（已完成）→ Plan（本文档）→ Build（逐阶段）→ Review（每阶段末）。

## Problem Statement / Motivation

需要一款 Liquid Glass 风格、双面板交互的 Android 文件管理器，覆盖「文件管理 → 文件编辑 → 压缩包 → APK 工具 → 系统工具」完整链路。
代码本地编写 + GitHub Actions 编译，任何阶段完成即可产出 APK 试用。

## Proposed Solution

- **技术栈**：Flutter 3.47.6 + flutter_miuix 1.3.0（HyperOS/Liquid Glass）；provider 状态管理
- **架构分层**：`core/`（模型+工具）→ `services/`（VFS/操作/设置）→ `ui/`（页面+组件）；VFS 抽象支持 本地/Root/压缩包 三种后端
- **自研引擎**：AXML 编解码、ARSC 解析、DEX 解析、APK v1/v2/v3 签名、WebDAV 客户端、文本对比引擎
- **验证链**：本地 `flutter analyze` 零错误 → push → Actions 编译 → artifact 下载

## Success Criteria

```yaml
success-criteria:
  - id: SC-1
    criterion: 本地静态分析零错误
    verify: cd /var/minis/workspace/jyfilemanager && flutter analyze --no-pub 2>&1 | grep -q "No issues found"
  - id: SC-2
    criterion: GitHub Actions 构建成功且产出 APK
    verify: gh run list -R Become-ILLUSORY/JYFileManager -L 1 --json conclusion -q '.[0].conclusion' | grep -q success
  - id: SC-3
    criterion: 双面板可同时浏览两个独立路径，复制操作面板间直达
    verify: manual 1.安装APK 2.左右面板分别进入不同目录 3.长按文件选复制 4.确认另一面板目录出现文件
  - id: SC-4
    criterion: 玻璃开关关闭后顶栏/底栏降级为纯色样式
    verify: manual 1.设置中关闭玻璃开关 2.返回主页确认无模糊层 3.重开恢复玻璃
  - id: SC-5
    criterion: 每里程碑的验收用例全部通过
    verify: manual 按各阶段 Acceptance 清单逐项核对
```

## Implementation Phases

### M0 基础设施（Status: In Progress）

**Scope**: 项目骨架、依赖、CI、主题桥接（玻璃开关）、VFS 抽象、本地/Root 文件系统、双面板主页、文件列表组件

**Files touched**: `pubspec.yaml` `lib/main.dart` `lib/ui/theme.dart` `lib/ui/pages/home_page.dart` `lib/ui/widgets/file_panel.dart` `lib/ui/widgets/file_list_tile.dart` `lib/services/fs/*` `lib/core/models/*` `.github/workflows/build.yml`

**Acceptance**:
- [x] 本地 flutter analyze 通过
- [x] 依赖解析成功（flutter_miuix 1.3.0 等 64 包）
- [ ] 修复当前 20 个分析问题（icon_utils 重复 case、vfs 导入、file_operations 哈希等）
- [ ] GitHub Actions 产出首个可安装 APK
- [ ] 双面板左右独立浏览 + 玻璃顶栏/底栏渲染

**Validation**: `flutter analyze` 零错误 → push → CI 绿 → artifact 含 APK

### M1 文件管理核心（Status: Pending）

**Scope**: 完整文件操作交互 —— 多选（滑动选择/全选/反选/类选）、排序、过滤（正则/否定）、路径跳转、书签面板、批量重命名（表达式引擎）、文件属性、打开方式管理、回收站删除

**映射**: A3 A4 A5 A6 A7 A8 A9 A10 A16

**Files touched**: `lib/ui/widgets/file_panel.dart`（手势多选）`lib/ui/pages/batch_rename_page.dart`（新建）`lib/services/rename_engine.dart`（新建）`lib/ui/widgets/bookmark_sheet.dart`（新建）`lib/ui/pages/settings_page.dart`（新建）

**Acceptance**:
- [ ] 左右滑动进入多选、头尾区间选择、全选/反选/类选
- [ ] 排序菜单 4 种 × 升降序、文件夹优先开关
- [ ] 过滤器支持 `关键字` `/正则` `!/否定`
- [ ] 长按返回键跳转任意路径
- [ ] 书签增删改 + 底栏上滑面板
- [ ] 批量重命名：`{N}{E}{zN}{P}{T}` 等表达式预览生效
- [ ] 设置页：主题模式、玻璃开关、排序偏好

**Validation**: analyze 零错误 + 手动验收清单 + CI 绿

### M2 文件编辑套件（Status: Pending）

**Scope**: 文本编辑器（多文件标签、行号、语法高亮、编码识别切换 GBK/UTF-8、查找替换、跳行）、Hex 编辑器（跳转/搜索/复制为 Base64/SHA1/MD5/CRC32/检查器/插入删除）、文件对比器（文本 diff 引擎）

**映射**: A14 A15 A11(文本部分)

**Files touched**: `lib/ui/pages/text_editor_page.dart` `lib/ui/pages/hex_editor_page.dart` `lib/ui/pages/diff_page.dart` `lib/services/diff_engine.dart` `lib/core/utils/text_codec.dart`（已备）

**Acceptance**:
- [ ] 文本编辑器打开 GBK/UTF-8 文件不乱码，可切换编码保存
- [ ] 查找替换（普通/正则）高亮定位
- [ ] Hex 编辑器跳转偏移、字节搜索、校验和面板
- [ ] 文本对比：行级 + 字符级高亮，大文件不卡顿

**Validation**: 用 1MB 文本、10MB Hex 文件实测 + CI 绿

### M3 压缩包与 APK 内浏览（Status: Pending）

**Scope**: zip/tar/gz/bz2 解压与创建；压缩包内浏览（VFS 第三后端）；APK/JAR 直接进入浏览；ZIP 增量修改（添加/替换/删除/重命名）；7z 支持评估

**映射**: A12 A13

**Files touched**: `lib/services/fs/archive_fs.dart`（新建）`lib/services/archive_service.dart`（新建）

**Acceptance**:
- [ ] 直接点开 zip/APK 像目录一样浏览
- [ ] 从压缩包复制文件到本地面板（双面板直接操作）
- [ ] 创建 zip/tar/tar.gz；解压全量/单文件
- [ ] ZIP 内文件替换后包结构完好（APK 签名场景）

**Validation**: 用真实 APK、多级目录 zip 实测 + CI 绿

### M4 APK 工具箱（Status: Pending）

**Scope**: APK 信息页（Manifest 解析/图标/权限/组件/DEX 列表/签名信息）、AXML 编解码引擎、ARSC 解析器、DEX 解析器（类/方法/字段/字符串浏览 + 搜索）、APK 签名（v1/v2/v3 生成、密钥管理）、自动签名、去除签名校验（基础版）

**映射**: B1 B6(浏览) B7 B8 B2(浏览+搜索) B4(浏览)

**Files touched**: `lib/services/axml/*`（新建）`lib/services/arsc/*`（新建）`lib/services/dex/*`（新建）`lib/services/apk_signer/*`（新建）`lib/ui/pages/apk_info_page.dart` 等

**Acceptance**:
- [ ] 打开 APK 显示应用名/包名/版本/权限列表/组件
- [ ] 图标提取预览、签名证书信息（SHA1/256）
- [ ] DEX 浏览器：类列表 → 方法/字段/字符串；全局搜索
- [ ] AXML 反编译为可读 XML；ARSC 资源树浏览
- [ ] 重新签名后的 APK 可安装且签名校验通过

**Validation**: 用真实 APK（含多 dex）逐项验证 + `apksigner` 验证签名（CI 或本地）

### M5 系统工具与远程（Status: Pending）

**Scope**: 终端模拟器（内置 shell + 常用命令集）、已安装应用列表（提取 APK/查看信息）、FTP/WebDAV 客户端（连接管理/远程浏览/上传下载）、ROOT 支持完善（挂载读写、su 管理）

**映射**: C1 C2 A19 A17 A18

**Files touched**: `lib/ui/pages/terminal_page.dart` `lib/ui/pages/apps_page.dart` `lib/services/remote/*`（ftp_client.dart webdav_client.dart 新建）

**Acceptance**:
- [ ] 终端可执行基础命令（ls/cat/cp/mv/rm 等）
- [ ] 应用列表过滤系统应用、搜索、一键提取 APK
- [ ] FTP 连接浏览下载；WebDAV 连接浏览（PROPFIND）
- [ ] ROOT 模式下读写 /data 目录

**Validation**: 真机 FTP/WebDAV 服务器联调 + CI 绿

### M6 高级逆向与 MCP（Status: Pending）

**Scope**: Dex 字符串解密（通用还原 + 自定义规则）、Dex 修复/合并、翻译模式（字典管理 + 应用汉化）、ARSC 编辑保存、XML 编辑保存、注入文件提供器、资源搜索/混淆、MCP 服务（HTTP 工具服务）

**映射**: B3 B5 B9 B10 B11 B12 B13 B14 B16

**Files touched**: `lib/services/dex/decrypt.dart` `lib/ui/pages/translation_page.dart` `lib/services/mcp/*`（新建）

**Acceptance**:
- [ ] 常见字符串加密样本可还原
- [ ] 翻译模式：字典导入 → ARSC 批量替换 → 重打包可运行
- [ ] AXML 编辑保存后 APK 正常解析
- [ ] MCP 服务暴露文件操作 + APK 工具接口

**Validation**: 真实样本端到端 + CI 绿

## 里程碑总表

| 里程碑 | 内容 | 功能映射 | 状态 |
|--------|------|----------|------|
| M0 | 基础设施 + 双面板骨架 | A1 A2 主题 | 进行中 |
| M1 | 文件管理核心交互 | A3-A10 A16 | 待开始 |
| M2 | 文本/Hex/对比编辑套件 | A11 A14 A15 | 待开始 |
| M3 | 压缩包 + APK 内浏览 | A12 A13 | 待开始 |
| M4 | APK 工具箱（信息/解析/签名） | B1 B2 B4 B6 B7 B8 | 待开始 |
| M5 | 终端/应用/远程/ROOT | A17 A18 A19 C1 C2 | 待开始 |
| M6 | 高级逆向 + MCP | B3 B5 B9-B14 B16 | 待开始 |

## Dependencies & Risks

- **7z/rar 解压**：Dart archive 包覆盖 zip/tar 系；7z 需捆绑外部二进制（风险：体积+许可），M3 评估后决策
- **DEX 编辑保存**：Smali 回编译规模大，先浏览后编辑（M4 浏览、M6 编辑）
- **签名 v2/v3**：需手写 APK Signing Block 构造（pointycastle 提供 RSA/SHA256 原语），参考 AOSP 格式文档
- **GitHub Actions 时长**：Flutter 构建约 8-15 分钟/次，用缓存 + 仅 push 触发控制成本
- **沙箱限制**：本地无法运行 Android 模拟器，UI 实测依赖用户真机安装反馈

## References & Research

### Internal
- 功能矩阵：`docs/FEATURES.md`
- Brainstorm：`docs/brainstorm/2026-10-06-jy-file-manager-full-feature-set-brainstorm-doc.md`
- 功能调研笔记：`docs/research-notes/`（35 页全文整理）
- flutter_miuix 源码研究：`research/flutter_miuix-src/`

### External
- flutter_miuix：https://pub.dev/packages/flutter_miuix
- APK 签名格式：https://source.android.com/docs/security/features/apksigning/v2
- AXML/ARSC 格式参考：androguard 文档
