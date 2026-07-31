# OpenClaw APK 内置运行环境设计方案

## 1. 文档目的

本文档定义 OpenClaw Android App 从“首次启动时联网下载安装环境”迁移到“APK 内置完整运行环境”的产品与技术方案。

目标是让用户安装 APK 后，无需理解 Ubuntu、RootFS、Node.js、npm 等技术概念，也无需在首次启动时下载大量文件或执行 `npm install`。用户只需同意协议，等待 App 在本地完成环境部署，即可进入首页配置 AI 提供商并开始使用。

本方案默认内置 OpenClaw `2026.3.23`，后续版本仍通过现有版本管理能力升级。

## 2. 核心目标

- APK 内置可直接运行的完整 OpenClaw 环境。
- 首次启动不依赖网络下载 Ubuntu、Node.js 和 OpenClaw。
- 首次启动不执行 OpenClaw 的完整 `npm install`。
- 用户界面不暴露 RootFS、Node.js、npm 等安装细节。
- 初始化失败后可以安全重试，不留下不可恢复的半安装状态。
- App 更新、OpenClaw 升级和环境修复不得覆盖用户配置与数据。
- 保留在线下载、本地导入和恢复内置版本等备用能力。
- 支持 ARM64，并为其他架构保留独立分包能力。

## 3. 非目标

- 本阶段不取消 OpenClaw 版本切换和在线升级。
- 本阶段不把 API Key 写入 APK 或预构建环境。
- 本阶段不把用户配置、工作区、聊天数据打进运行环境镜像。
- 本阶段不保证一个 APK 同时内置 ARM64、ARMv7 和 x86_64 的完整环境。
- 本阶段不直接删除现有在线安装逻辑，在线逻辑继续作为兼容与恢复路径保留。

## 4. 产品形态

建议发布两种安装包。

### 4.1 完整版

- 内置完整运行环境。
- APK 体积较大。
- 首次启动只进行本地解压、配置和验证。
- 推荐普通用户使用。

建议名称：

```text
OpenClaw 完整版 ARM64
```

### 4.2 轻量版

- 不内置完整运行环境。
- APK 体积较小。
- 首次启动按现有流程联网下载所需组件。
- 用作存储空间有限、特殊架构或完整包兼容失败时的备用方案。

建议名称：

```text
OpenClaw 轻量版 ARM64
```

## 5. APK 内容结构

完整版 APK 建议采用以下结构：

```text
APK
├── Flutter App
├── Android 原生代码
├── PRoot 与相关原生运行库
├── App 图标、字体和界面资源
└── assets/runtime/
    ├── runtime-manifest.json
    ├── openclaw-runtime-2026.3.23-arm64.tar.zst
    └── openclaw-runtime-2026.3.23-arm64.tar.zst.sha256
```

不建议在完整版中同时内置以下三个相互重叠的资源：

```text
Ubuntu Base
Node.js 压缩包
OpenClaw 预构建 RootFS
```

推荐在发布构建阶段将它们合并为一个已经安装完成的运行环境镜像。手机端只处理一个镜像，能够减少重复数据、安装分支和失败点。

## 6. 完整运行环境镜像

### 6.1 镜像内容

预构建镜像至少包含：

- Ubuntu 24.04 ARM64 RootFS。
- CA 证书、Git、Python、编译工具和必要系统依赖。
- 已验证的 Node.js ARM64 版本。
- npm、Corepack 及 OpenClaw 所需依赖。
- OpenClaw `2026.3.23`。
- OpenClaw 命令入口和可靠的 wrapper。
- Bionic Bypass。
- PRoot 环境所需的 DNS、环境变量和启动脚本模板。
- 初始化验证脚本。

### 6.2 镜像中不得包含

- 真实 API Key、Token 和密码。
- 开发者本机路径。
- npm、GitHub 或镜像站登录凭据。
- 用户工作区和个人配置。
- 构建日志、下载缓存和无用临时文件。
- SSH 私钥和设备标识。

### 6.3 镜像清理

打包前应清理：

- `/tmp` 和 `/var/tmp`。
- apt 缓存与软件包索引。
- npm 缓存。
- 构建中间文件。
- 日志文件。
- Shell 历史。
- 测试配置。

### 6.4 压缩格式

优先评估 `tar.zst`，原因如下：

- 解压速度通常优于 `tar.gz`。
- 适合首次启动时大量小文件释放。
- 可在压缩率和初始化速度之间调整等级。

如果 Android 端引入 Zstandard 会明显增加复杂度，可以第一阶段继续使用 `tar.gz`，待流程稳定后再切换。

## 7. 运行环境清单

APK 内置 `runtime-manifest.json`，示例：

```json
{
  "schemaVersion": 1,
  "runtimeRevision": 1,
  "architecture": "arm64-v8a",
  "ubuntuVersion": "24.04.3",
  "nodeVersion": "24.18.1",
  "openclawVersion": "2026.3.23",
  "archive": "openclaw-runtime-2026.3.23-arm64.tar.zst",
  "archiveSha256": "待构建时生成",
  "minimumFreeSpaceBytes": 1073741824,
  "createdAt": "待构建时生成"
}
```

App 使用该清单完成：

- 架构匹配检查。
- 镜像完整性验证。
- 磁盘空间检查。
- 已安装运行环境版本识别。
- App 更新后的运行环境迁移判断。
- 恢复内置版本。

`runtimeRevision` 用于处理 OpenClaw 版本相同但运行环境内容发生变化的情况。

## 8. 首次启动用户流程

### 8.1 欢迎与协议页面

建议文案：

```text
欢迎使用 OpenClaw

OpenClaw 会在本机创建独立的 AI 助手运行环境。
首次准备大约需要 1～3 分钟，期间请保持应用在前台。
```

页面包含：

- 用户协议入口。
- 隐私政策入口。
- 同意选项。
- “同意并继续”按钮。

用户同意状态需要持久化；协议版本发生变化时可以要求重新确认。

### 8.2 初始化页面

普通用户界面不显示 Ubuntu、RootFS、Node.js、npm 等术语。

推荐显示以下阶段：

```text
正在检查设备环境……
正在准备运行环境……
正在部署核心组件……
正在配置本地服务……
正在进行最后检查……
```

辅助说明：

```text
首次准备可能需要几分钟，请不要退出应用。
所有核心组件均从安装包本地部署，不会消耗下载流量。
```

界面提供一个总进度条。详细技术日志只在“查看详情”中展示，不默认打扰用户。

### 8.3 初始化完成

初始化验证成功后显示：

```text
OpenClaw 已准备完成
```

随后自动进入首页。首页负责引导用户选择 AI 提供商、填写 API Key 和选择模型。

## 9. 首次初始化技术流程

```text
启动 App
  ↓
检查协议状态
  ↓
读取 runtime-manifest.json
  ↓
检查 CPU 架构、系统版本和可用空间
  ↓
检查现有运行环境
  ├── 完整且版本匹配 → 进入首页
  ├── 可修复 → 执行轻量修复并验证
  └── 不存在 → 部署内置镜像
                    ↓
              校验镜像 SHA-256
                    ↓
              解压到 staging 目录
                    ↓
              写入设备专属配置
                    ↓
              安装/刷新运行 wrapper
                    ↓
              创建最小 OpenClaw 配置
                    ↓
              验证 Node、OpenClaw、Gateway
                    ↓
              原子切换为正式运行目录
                    ↓
                 进入首页
```

## 10. 原子部署与中断恢复

禁止直接将镜像解压到正式 RootFS。

推荐目录结构：

```text
files/
├── runtime/
│   ├── current.json
│   └── installation.lock
├── rootfs/
│   └── ubuntu/
├── rootfs-staging/
│   └── ubuntu/
└── user-data/
```

部署流程：

1. 创建安装事务和 `installation.lock`。
2. 清理上一次失败遗留的 staging 目录。
3. 将镜像解压到 `rootfs-staging`。
4. 检查关键文件、权限、符号链接和版本。
5. 写入设备专属文件。
6. 完成运行测试。
7. 将旧 RootFS 移动到可回滚目录。
8. 将 staging 原子切换为正式 RootFS。
9. 写入 `current.json`。
10. 删除安装锁和旧环境。

如果 App 被系统杀死，下次启动读取安装锁并自动执行安全清理或继续恢复，不得把半成品当作完整环境启动。

## 11. 设备专属配置

以下内容不能在构建阶段固定，应在手机端初始化时生成：

- Android UID/GID 映射。
- DNS 与 `resolv.conf`。
- `/etc/hosts`。
- PRoot 运行路径。
- App 私有目录路径。
- Gateway Token。
- 最小 `openclaw.json`。
- `.env` 中的非敏感默认值。
- 文件权限和可执行位。
- Bionic Bypass 与 Node wrapper 的实际路径。

默认最小配置只保证 Gateway 可以启动，不预置第三方 AI 提供商和 API Key。

## 12. 运行环境与用户数据分离

这是该方案必须同步推进的设计原则。

### 12.1 可重建运行环境

- Ubuntu 系统文件。
- Node.js。
- npm 全局包。
- OpenClaw 程序文件。
- wrapper 与兼容脚本。

### 12.2 不可覆盖用户数据

- `openclaw.json`。
- `.env`。
- API Key 和提供商配置。
- Gateway Token。
- Agents、Workspace、Memory。
- 聊天记录和用户安装的扩展。
- 用户导入的文件。

长期建议将用户数据迁移到 RootFS 外部的独立目录，再通过绑定挂载或符号链接提供给 OpenClaw。这样“恢复内置环境”可以重建整个 RootFS，而不会触碰用户数据。

## 13. 初始化验证

镜像解压完成后至少验证：

```text
/bin/sh 存在且可执行
/usr/bin/env 存在
/usr/local/bin/node 存在且可执行
node --version 返回清单中的兼容版本
npm --version 可执行
/usr/local/bin/openclaw 存在
openclaw --version 返回 2026.3.23
Bionic Bypass 文件存在
OpenClaw 最小配置可解析
Gateway 可以启动并响应健康检查
```

只检查文件存在是不够的，必须实际运行 Node 和 OpenClaw。真我 Neo 7 Turbo 已经证明“文件成功解压”不代表“二进制可以在设备上执行”。

## 14. 兼容性设计

### 14.1 CPU 架构

每个完整运行环境必须与 APK 架构一致：

- ARM64 APK 内置 ARM64 环境。
- ARMv7 APK 内置 ARMv7 环境。
- x86_64 APK 仅用于模拟器或开发测试。

不要在同一个 APK 中放入所有架构的完整 RootFS，否则体积会过大。

### 14.2 4KB 与 16KB 内存页

需要在初始化前读取设备页大小，并在运行验证中记录：

```text
getconf PAGESIZE
```

测试范围必须覆盖：

- 4KB 页设备。
- 16KB 页设备。
- 高通平台。
- 联发科平台。
- Android 12～16。

Node.js、PRoot loader 和相关原生库必须分别验证。若无法提供一个通用 Node 构建，应在镜像清单中声明兼容范围，或按设备能力选择不同运行文件。

### 14.3 存储空间

安装前需要同时考虑：

- APK 本身体积。
- APK 安装后的占用。
- 镜像解压后的 RootFS。
- staging 与正式 RootFS 短暂并存。
- 后续升级和用户数据空间。

第一版建议要求至少 1～1.5 GB 可用空间，实际阈值根据最终镜像大小测试后确定。

### 14.4 厂商安全策略

继续使用稳定、长期保留的正式 Keystore。发布包不得使用 Android Debug 证书。

需要在以下系统上进行安装与首次启动测试：

- realme UI。
- ColorOS。
- OriginOS。
- HyperOS。
- One UI。
- 原生或接近原生 Android。

## 15. 版本升级

### 15.1 首次版本

APK 默认内置 OpenClaw `2026.3.23`，并在版本选择中标记为推荐稳定版本。

### 15.2 后续 OpenClaw 升级

后续升级继续使用现有版本服务：

- 获取版本列表。
- 检查 Node.js 要求。
- 下载对应 OpenClaw 包。
- 执行受保护升级。
- 保留用户配置。
- 升级失败自动回滚。

首次安装不运行 `npm install`，不代表后续升级永远不运行。后续版本如依赖发生变化，仍可能需要安装或更新 npm 依赖。

### 15.3 恢复内置版本

设置或恢复页面提供：

```text
恢复 APK 内置的 OpenClaw 2026.3.23
```

恢复操作只替换可重建运行文件，不删除用户数据。执行前必须建立恢复事务，并在失败时回滚。

### 15.4 App 更新

App 更新后按以下规则处理：

- 已有环境完整且兼容：直接复用，不重复解压。
- `runtimeRevision` 提升且仅需修复文件：执行增量修复。
- 环境损坏：优先恢复内置镜像。
- 用户主动选择重建：重新部署内置镜像并保留用户数据。

## 16. 备用与恢复路径

完整版仍保留以下能力：

- 重新部署内置环境。
- 修复运行文件。
- 从本地文件导入运行环境镜像。
- 从网络下载运行环境镜像。
- 查看详细初始化日志。
- 导出诊断信息。
- 恢复内置 OpenClaw 版本。

普通初始化页面只展示简洁信息，恢复页面才展示技术选项。

## 17. 错误呈现

普通错误提示需要对用户友好，例如：

```text
运行环境准备失败
请确认设备剩余空间充足，然后重试。
```

同时提供：

- 重试。
- 查看详情。
- 导出诊断日志。
- 使用轻量版/在线安装。

详细错误不得被统一吞成 `not detected`。诊断信息至少包含：

- 当前初始化阶段。
- 设备架构和页大小。
- 运行环境清单版本。
- 失败命令退出码。
- stderr 或合并输出的最后若干行。
- staging 和正式目录状态。
- 剩余空间。

日志中必须隐藏 API Key、Token 和其他敏感数据。

## 18. 构建流水线

建议新增独立的运行环境构建脚本，流程如下：

```text
准备 Ubuntu Base
  ↓
安装系统依赖
  ↓
安装并验证 Node.js
  ↓
安装 OpenClaw 2026.3.23
  ↓
安装兼容脚本与 wrapper
  ↓
执行运行测试
  ↓
清理缓存和构建残留
  ↓
生成 runtime-manifest.json
  ↓
压缩运行环境
  ↓
生成 SHA-256
  ↓
放入 Flutter/Android 构建资源
  ↓
构建 ARM64 Release APK
  ↓
使用正式 Keystore 签名
```

构建必须可重复，不能依赖开发者手工进入 RootFS 修改文件后再打包。

## 19. 建议模块划分

建议新增或调整以下模块：

```text
RuntimeManifest
  解析和验证内置运行环境清单

BundledRuntimeService
  定位、复制和校验 APK 内置镜像

RuntimeInstaller
  staging 解压、事务、原子切换与回滚

RuntimeCompatibilityService
  架构、Android 版本、页大小和存储空间检查

RuntimeVerificationService
  Node、OpenClaw、Gateway 的实际运行验证

RuntimeRecoveryService
  修复、恢复内置版本和在线回退

UserDataLayoutService
  用户数据与运行环境的分离及迁移
```

现有 `BootstrapService` 可以逐步退化为编排层，不再同时承担下载、安装、解压、验证和恢复等所有职责。

## 20. 分阶段实施计划

### 阶段一：运行环境镜像原型

- 制作包含 Ubuntu、Node.js 和 OpenClaw `2026.3.23` 的完整 ARM64 RootFS。
- 清理缓存与敏感数据。
- 生成清单和 SHA-256。
- 在模拟器与至少两台 ARM64 真机手动解压并验证。

通过标准：

- 解压后无需联网即可运行 `node --version`。
- 无需 `npm install` 即可运行 `openclaw --version`。
- Gateway 可以启动。

### 阶段二：内置镜像部署器

- APK 打入完整镜像。
- 实现清单解析与 SHA-256 校验。
- 实现 staging 解压、安装锁和原子切换。
- 实现中断恢复。

通过标准：

- 飞行模式下能够完成首次部署。
- 初始化中途强制结束 App 后可以安全重试。
- 失败不会破坏已有完整环境。

### 阶段三：首次启动界面

- 新增欢迎与协议页。
- 将技术安装步骤替换为通用初始化阶段。
- 增加总体进度、查看详情、重试和日志导出。
- 成功后自动进入首页。

通过标准：

- 普通用户无需理解 Ubuntu、Node.js 和 npm。
- 首次启动不要求用户回答终端交互问题。
- 初始化成功后直接进入首页配置 AI。

### 阶段四：用户数据分离与恢复

- 明确可重建运行环境与持久用户数据边界。
- 实现恢复内置版本。
- 实现 App 更新后的环境复用和修复。
- 验证版本升级/降级不覆盖用户数据。

通过标准：

- 重建 RootFS 后 API Key、配置和工作区仍然存在。
- OpenClaw 升级失败可以回滚。
- App 更新不重复部署相同运行环境。

### 阶段五：兼容性与发布

- 测试 4KB/16KB 页设备。
- 测试高通和联发科平台。
- 测试 Android 12～16。
- 测试 realme UI、ColorOS、OriginOS、HyperOS 和 One UI。
- 使用正式 Keystore 签名。
- 同时发布完整版和轻量版。

通过标准：

- 核心设备矩阵首次初始化通过。
- 无网络条件下完整安装成功。
- 厂商安全中心不存在无法绕过的阻断。
- APK、解压空间和初始化耗时符合发布要求。

## 21. 测试清单

### 21.1 安装测试

- 全新安装。
- 覆盖升级 App。
- 从轻量版迁移到完整版。
- 从完整版迁移到新版完整版。
- 存储空间不足。
- 镜像损坏。
- 架构不匹配。

### 21.2 中断测试

- 解压 10% 时结束进程。
- 解压 90% 时结束进程。
- 配置阶段结束进程。
- Gateway 验证阶段结束进程。
- 初始化时重启手机。

### 21.3 运行测试

- Node.js 版本检测。
- npm 可执行。
- OpenClaw 版本检测。
- Gateway 启停。
- 首页 Dashboard 打开。
- AI 提供商配置和模型测试。

### 21.4 数据保护测试

- 恢复内置版本保留 API Key。
- 重建环境保留 Gateway Token。
- 升级/降级保留 Workspace。
- 失败回滚保留原环境和用户数据。

## 22. 发布验收标准

完整版 APK 发布前必须满足：

- 飞行模式下完成首次初始化。
- 首次初始化不下载 Ubuntu、Node.js 或 OpenClaw。
- 首次初始化不执行完整 `npm install`。
- 默认 OpenClaw 版本为 `2026.3.23`。
- 初始化成功后直接进入首页。
- 用户可以在首页配置 AI 提供商。
- 初始化中断后可以安全重试。
- 内置镜像 SHA-256 校验有效。
- Node、OpenClaw 和 Gateway 均经过实际运行验证。
- 恢复内置版本不会删除用户数据。
- APK 使用长期保留的正式 Keystore 签名。
- ARM64 APK 只包含 ARM64 原生库和 ARM64 运行环境。
- 4KB 与 16KB 页设备的兼容结论明确。

## 23. 最终决策摘要

本方案采用以下产品与技术决策：

1. 默认发布带完整运行环境的 ARM64 完整版 APK。
2. APK 内置一个完整预构建 RootFS，而不是三个独立且内容重叠的安装包。
3. 预构建 RootFS 默认包含 OpenClaw `2026.3.23`。
4. 手机首次启动只执行校验、解压、设备配置和运行验证。
5. 用户只看到欢迎协议、通用初始化进度和完成页面。
6. 部署采用 staging、事务、原子切换和失败回滚。
7. 用户数据与运行环境分离，恢复环境不得删除用户数据。
8. 在线安装逻辑保留为轻量版和故障回退能力。
9. 后续 OpenClaw 版本继续通过现有升级机制安装。
10. 在正式发布前必须解决并验证 16KB 内存页设备上的 Node.js 与 PRoot 兼容性。
