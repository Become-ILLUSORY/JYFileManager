# JY文件管理器 — 完整功能矩阵（业界功能调研 2026-10-06）

来源：功能调研存档 research/mt-guide-text/

## A. 文件管理（核心）
- [ ] A1 双窗口操作：左右两个文件列表，复制/移动直接从当前窗口到另一窗口（无粘贴步骤）
- [ ] A2 同步功能：点击同步按钮另一窗口立即与当前窗口同步；压缩包内点击同步定位到压缩包所在位置
- [ ] A3 前进/后退：每个窗口独立的导航历史
- [ ] A4 文件多选：左右滑动进入多选；连续滑动头尾选中区间；全选/反选/类选（选同类型文件）
- [ ] A5 书签功能：常用路径/文件加书签，底栏上滑调出书签面板
- [ ] A6 过滤功能：长按同步按钮输入关键字过滤；`/正则`、`!/`否定正则、`!`否定匹配
- [ ] A7 路径跳转：长按返回上级按钮输入路径跳转
- [ ] A8 文件排序：名称/大小/时间/类型，升降序，文件夹优先
- [ ] A9 批量重命名：表达式 {P}{S}{T}{N}{zN}{E}{AN}{AP}{AV}{AC}
- [ ] A10 日期时间表达式：y yy MMMM dd EEE HH hh mm ss SSS Q 等完整模式
- [ ] A11 文件对比器：文本/DEX/ARSC/AXML/APK-ZIP/文件夹 6 种对比
- [ ] A12 压缩文件：解压（zip/7z/rar/tar/gz/bz2/xz）；创建 zip/7z/tar/tar.gz/tar.bz2
- [ ] A13 ZIP 增强：APK/JAR 内部浏览、增量添加/修改/重命名(移动)/删除
- [ ] A14 文本编辑器：多文件编辑、保留文件、排序置顶、ASCII 控制字符显示、行号长按选中、流畅模式、切换注释、压缩/格式化代码、替换行、换行符设置
- [ ] A15 Hex 编辑器：复制/复制为…（Base64/SHA1/MD5/CRC32）、粘贴/粘贴从…、搜索替换、检查功能（十进制/浮点/高字节优先）、删除/插入数据
- [ ] A16 文件打开方式：15 种内置打开方式、设置默认、管理、排序
- [ ] A17 ROOT 相关：获取 root 权限、自定义 su 命令、自动挂载读写
- [ ] A18 应用数据目录规范：DEBUG.log/apks/openMethod/dictionary/keystore/keys/logs 等
- [ ] A19 安装包提取：已安装应用 → 提取 APK 到指定目录
- [ ] A20 本地存储：无 ROOT 访问 data 目录（DocumentsProvider 方案）

## B. 逆向修改（APK 工具箱）
- [ ] B1 APK 信息：Manifest 解析（应用名/包名/版本/权限/组件）、图标提取、DEX 列表、签名信息
- [ ] B2 Dex 编辑器++：Smali 反编译浏览、代码导航（字段/方法/字符串）、代码跳转、指令查询、寄存器分析、搜索（代码/类名/方法/字段/字符串/整数，正则）、替换、工程管理
- [ ] B3 转成 Java：多引擎反编译（Jadx/FernFlower/JD-Core/Procyon/CFR）
- [ ] B4 Arsc 编辑器：包/类型/配置/条目/值 五层结构浏览编辑、添加配置、添加条目
- [ ] B5 Arsc 编辑器++：树状结构、package-info/type-info/资源数据文件、工程
- [ ] B6 Xml 编辑：二进制 AXML 反编译↔编译、字符常量池、ID 转名称、自动补全
- [ ] B7 APK 签名：签名密钥生成/导入/导出/管理、v1/v2/v3 签名、自动签名
- [ ] B8 去除签名校验：一键去除 APP 自校验
- [ ] B9 Dex 字符串解密：多款字符串加密工具还原、加强版算法、自定义解密函数（通配符）
- [ ] B10 Dex 修复 / 合并与重划分
- [ ] B11 翻译模式：APP 汉化、字典管理、Arsc 翻译
- [ ] B12 注入文件提供器：无 ROOT data 访问方案
- [ ] B13 注入日志记录：注入方案管理
- [ ] B14 APK 克隆 / 资源混淆 / 资源搜索
- [ ] B15 应用保护（服务端混淆，已停止出售→不实现）
- [ ] B16 MCP 服务：HTTP 服务器 + APK/ZIP/文件工具供 AI 调用

## C. 工具与系统
- [ ] C1 终端模拟器：bash 会话、coreutils/findutils/gawk/grep/sed/openssl/openssh/wget/curl/iconv/zip/bzip2/zstd/lz4/brotli/adb、su 包装、会话管理、复制粘贴
- [ ] C2 已安装应用：应用列表、系统应用过滤、搜索、提取
- [ ] C3 签名密钥管理界面
- [ ] C4 侧拉栏：工具分组、工程分组、书签
- [ ] C5 设置：主题、root、打开方式排序、编辑器偏好、底部工具栏边距等

## 设计语言
- Liquid Glass（OS4 玻璃材质）：MiuixGlassTopAppBar / MiuixGlassNavigationBar / MiuixGlassDialog / MiuixGlassPopup
- flutter_miuix 1.3.0（HyperOS 风格）：squircle 圆角、Folme 弹簧动效、Monet 动态取色
- 双面板布局：左右独立浏览 + 中央分隔 + 玻璃工具栏

## 技术栈
- Flutter 3.47.6 / Dart 3.13.5（本地 arm64 沙箱可 flutter analyze）
- flutter_miuix 1.3.0、provider、archive、crypto、pointycastle、enough_convert、re_highlight、shared_preferences、ftpconnect、permission_handler、xml、image、intl
- 自研：AXML 编解码、ARSC 解析、DEX 解析、APK 签名(v1/v2/v3)、WebDAV 客户端、文件对比引擎
- 编译：GitHub Actions (x64 runner) → APK artifact

## 里程碑
- M1 双面板核心 + 文件操作 + 主题（本批）
- M2 压缩包 + 文本/Hex 编辑器
- M3 APK 工具箱（信息/Manifest/Dex/Arsc/签名）
- M4 对比器/批量重命名/终端/已安装应用
- M5 MCP 服务 + 高级逆向工具
