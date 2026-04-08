# Changelog

## v1.9.9 - 维护备份升级、工作目录恢复与发布链路准备

### 关键改动

- **维护页升级为更通用的备份入口**：设置页现在可导出两种备份，一种是仅包含 `openclaw.json` 的配置文件，另一种是带标识的工作目录压缩包；导入时会自动识别配置 JSON、旧版快照 JSON 和工作目录 ZIP，不再要求用户先手动选择类型。
- **工作目录备份覆盖配置、记忆与会话沉淀**：新增工作目录备份/恢复链路，聚焦 `/root/.openclaw` 下的 `openclaw.json`、`.env`、`memory`、`agents`、`skills`、`config`、`extensions` 等核心数据，便于迁移历史配置、恢复记忆和保留会话上下文。
- **工作目录恢复增加安全边界**：导入工作目录备份前会先停止网关，只允许恢复白名单路径，并校验 ZIP 标识、内部条目和路径边界，避免无边界覆盖整个 rootfs 或误导入普通压缩包带来的状态损坏。
- **安装向导同步支持新备份导入**：首次安装完成后的导入入口也已切换到新备份识别逻辑，可直接恢复配置文件、旧快照或工作目录备份。
- **正式发布元数据同步到 `v1.9.9`**：应用版本、CLI 版本、README、发布目录与中文/英文说明同步更新到 `v1.9.9`，Android 构建号递增到 `44`，用于后续正式打包发布。

## v1.9.8 - 离线引导资源、真实安装进度与网关状态同步优化
### 关键改动

- **初始化支持离线 RootFS / Node.js 24 优先复用**：安装流程现在会优先使用 APK 内置或本地缓存的 `ubuntu-base-24.04.3-base-arm64.tar.gz` 与 `node-v24.14.1-linux-arm64.tar.xz`，只有本地资源不存在或解压失败时才回退到在线下载，减少重复初始化时的等待和流量消耗。
- **安装过程补齐实时速度、预计时间与滚动日志**：安装向导和首页“安装所选版本”现在都会展示更真实的下载大小、当前速度、ETA 与细粒度状态文案，并把基础包安装、npm 安装等实时日志以小字详情持续滚动显示，减少“进度条像假的”与“长时间不知道在做什么”的体验问题。
- **APT 镜像与 OpenClaw 安装链路优化**：Ubuntu 基础包安装前会自动探测更快的镜像源；OpenClaw 版本安装改为优先下载 npm tarball 到本地缓存，并细化到依赖安装、bin wrapper 创建、版本校验等阶段，同时支持复用已安装运行时，降低网络抖动导致的重复工作。
- **网关首页状态绑定与配置生效时机更稳定**：首页控制台地址会优先从配置文件同步并更快刷新；健康检查与状态切换更及时；保存模型或通道配置后改为优先走热重载/状态同步，避免重复 stop/start 带来的错位日志和状态闪烁。
- **设置布局与正式发布元数据同步**：设置页把“维护”区域移动到“系统信息”上方；应用内安装状态提示补齐多语言本地化；Android 正式包名恢复为 `com.junwan666.openclawzh`，应用版本、CLI 版本、README 与发布目录统一同步到 `v1.9.8`，Android 构建号递增到 `43`。

## v1.9.7 - 版本安装保护、快照版本校验与网关鉴权稳定性修复

### 关键改动

- **安装所选版本增加保护**：首页“安装所选版本”新增二次确认弹窗；如果当前已安装的版本与所选版本一致，会直接提示“已是当前版本”并禁用重复安装入口，避免手滑误触后重复下载。
- **快照导出/导入携带版本信息**：快照导出文件名现在会自动拼接 App 版本与 OpenClaw 版本；导入时会先分析快照与当前环境的版本差异，如果缺少版本信息或版本不一致，会先弹出提醒再决定是否继续恢复。
- **网关 token 优先从配置文件读取**：新增 `GatewayAuthConfigService`，优先从 `openclaw.json` 与 `.env` 解析 `gateway.auth.token`，首页控制台地址与 Node 连接都会优先使用配置中的 token，不再过度依赖日志抓取或历史缓存 URL。
- **兼容日志降噪与状态同步优化**：过滤掉 `xai-auth bootstrap config fallback`、`boot-md skipped` 等低价值噪声日志，并将本地兼容模式、Bonjour 重试、模型定价超时等常见 Android 场景重写为更易理解的提示；网关状态同步也更保守，降低 Web UI 返回首页后误显示“已停止”的概率。
- **RootFS 时区与 cpolar DNS 兜底**：Ubuntu RootFS 启动/修复时会默认写入 `Asia/Shanghai` 时区；cpolar 初始化前会额外确保 `config/resolv.conf` 与 RootFS 内 `etc/resolv.conf` 都存在，减少因 DNS 文件缺失导致的启动失败。
- **版本元数据同步到正式版 1.9.7**：应用内版本号、CLI 版本号、发布说明与发布目录统一更新到 `v1.9.7`，Android 构建号递增到 `40`。

## v1.9.6 - cpolar、消息平台初始化修复与网关状态同步

### 关键改动

- **新增 cpolar 可选组件**：在“可选组件”页面加入 cpolar，一站式提供安装、卸载、启动、停止、状态显示、Web 面板入口，以及安装过程中的实时日志滚动输出，方便直接在应用内完成穿透服务准备。
- **QQ / 微信接入初始化修复**：补齐 PRoot 原生运行时兜底逻辑，启动消息平台相关命令前会先准备 `libproot.so`、loader 与 DNS 配置；当部分设备未正确挂载原生库目录时，也能从 APK 中回退提取，修复插件初始化阶段的 `Native runtime binary is missing: libproot.so` 问题。
- **首页控制台地址与运行状态更稳定**：Dashboard URL 解析现在会自动清理误拼接到 token 后面的 `copy`、`copied`、`GatewayWS` 等噪声后缀；从 Web 控制台返回首页后会主动重新同步网关状态，尽量避免“实际仍在运行但首页显示已停止”的错位情况。
- **OpenClaw 版本切换增加进度百分比**：首页切换 OpenClaw 版本时，安装进度条旁会实时显示百分比，长时间安装时反馈更直观。
- **关键配置支持自动应用**：修改模型提供商、消息平台等关键配置后，如果网关当前正在运行，应用会自动重启网关以应用新配置，并在日志中明确记录应用过程；若网关未运行，则会提示下次启动生效。
- **版本元数据同步到正式版 1.9.6**：应用内版本号、CLI 版本号、发布产物命名与本次发布目录统一收口到 `v1.9.6`，并将 Android 构建号递增到 `39`，便于从测试包平滑覆盖安装。

## v1.9.5 - 快照导出选位置与智谱 AI 适配

### 关键改动

- **快照导出改为系统保存面板**：设置页导出快照时改为直接调用 Android 系统保存面板，可自行选择保存位置与文件名，不再把备份固定写入应用私有目录。
- **原生桥接补齐快照写入链路**：Android 原生侧新增快照写入能力，导出完成后会返回真实保存的文件名，便于确认备份位置与结果。
- **新增独立的智谱 AI 提供商**：AI 提供商列表新增 `智谱 AI`，内置官方基础地址 `https://open.bigmodel.cn/api/paas/v4` 与常用 `GLM` 模型预设。
- **自定义提供商适配智谱兼容模式**：新增 `智谱 AI Compatible` 兼容模式；当基础地址为 `bigmodel.cn` 时，会优先按智谱规则测试和保存，不再错误补成 `/v1`。
- **多语言文案与测试同步**：简中、繁中、英文、日文的智谱与快照相关提示文案同步更新，自定义提供商连接测试也补充了对应自动识别与地址归一化测试。

## v1.9.4 - 首页控制台 Token URL 双重保险

### 关键改动

- **首页控制台地址补全更稳**：修复部分用户在安装完成或网关重启后，首页控制台地址没有自动带上 `#token=` 的问题；现在会优先从日志提取 token URL。
- **主动探测补齐 token**：当日志里没有及时出现完整 token URL 时，应用会在网关健康后主动向控制台发起探测，请求补全首页地址中的 `#token=`。
- **token URL 解析兼容性增强**：不再只依赖 `localhost` / `127.0.0.1` 的固定格式，同时支持 query / fragment token 和部分响应体里的 token 信息。
- **启动时序优化**：启动网关时改为先订阅日志再拉起网关进程，减少因监听过晚导致首条控制台地址漏抓的问题。
- **Node 与 CLI 元数据同步**：统一 Node 侧读取网关 token 的解析逻辑，并修正 CLI 脚本中的版本号显示，避免版本元数据不一致。

## v1.9.3 - 应用内更新安装权限引导修复

### 关键改动

- **应用内更新安装链路修复**：修复更新包下载完成后直接跳回浏览器下载页的问题；现在会优先尝试调起 Android 系统安装器。
- **补齐未知来源安装权限引导**：当设备尚未允许 OpenClaw 安装未知应用时，更新流程会先打开系统授权页；授权返回后会继续尝试安装，不需要手动重新找安装包。
- **失败回退更准确**：只有真正无法在应用内继续安装时，才会回退到浏览器下载页，并展示更明确的错误提示。
- **多语言提示同步**：同步补充简中、繁中、英文、日文的安装权限提示文案，让不同语言界面的更新反馈保持一致。

## v1.9.2 - 首页更新提醒按钮与统一更新入口

### 关键改动

- **首页更新提醒更直观**：在首页左上角 `OpenClaw` 标题右侧新增轻量化的检查更新按钮，默认保持低存在感；当检测到新版本时，会切换为更明显的更新样式并附带红点提示。
- **静默刷新更新状态**：首页会在首次进入、应用回到前台，以及从设置等页面返回后静默刷新版本状态，减少必须手动进入设置页检查的步骤。
- **更新流程入口统一**：首页标题按钮和设置页“检查更新”现在共用同一套下载、安装和失败回退逻辑，体验更一致。

## v1.9.1 - QQ / 微信接入与应用内更新安装

### 关键改动

- **QQ 机器人接入**：新增 QQ 机器人接入页，进入页面后会自动检测并安装 `@tencent-connect/openclaw-qqbot@latest` 插件，可快捷打开腾讯 QQ Bot 接入页面；保存时会执行 `openclaw channels add --channel qqbot --token "<AppID>:<AppSecret>"` 完成绑定。
- **微信接入引导**：新增微信接入入口与独立绑定终端，可检测微信插件状态，并一键执行 `npx -y @tencent-weixin/openclaw-weixin-cli install`；终端中的二维码或登录链接可直接扫码、截图或复制后继续绑定。
- **应用内更新下载与安装**：检查更新会从 GitHub Release 读取全部安装包，自动识别当前机型并优先下载对应 APK；下载完成后会直接调起 Android 系统安装器。
- **失败自动回退到浏览器**：如果应用内下载或安装失败，会自动回退到浏览器打开对应 Release 下载页，避免更新链路卡死。
- **安装桥接能力补齐**：新增安装器调用链路、相关权限与 ABI 选择测试覆盖，提升应用内更新稳定性。

## v1.9.0 - 自定义兼容提供商、API 检测与安装引导权限修正

### 关键改动

- **自定义兼容提供商扩展**：新增独立的自定义提供商详情页，可保存多个预设，并支持 OpenAI Chat Completions、OpenAI Responses、Anthropic Messages、Google Generative AI 兼容模式与自动识别。
- **保存前自动检测 API**：自定义提供商新增“测试连接”与保存前自动检测；当 API 不可用时会展示失败原因，并由用户决定是否继续保存。
- **首页版本状态提示重构**：首页网关卡片的版本状态提示已改为“已选版本 + 是否可更新”的表达，减少“当前最新”带来的误导。
- **安装引导导入快照更克制**：安装引导完成页仍支持直接导入快照；但在安装引导场景恢复快照时，不再自动重新启用 Node，避免旧快照触发整套 Node 权限申请。
- **仓库发布元数据同步**：应用内 GitHub 链接、版本检查来源与 CLI 版本号统一对齐到本仓库的 1.9.0 发布链路。

## v1.8.9 - 可选 OpenClaw 版本、快照恢复与日志持久化

### 关键改动

- **OpenClaw 版本选择**：安装首页与首页网关卡片都可拉取已发布版本，默认选中最新版本，也可手动安装、重装、升级或降级指定版本。
- **版本安装链路增强**：版本选择会同步展示对应安装体积和 Node.js 要求；如内置 Node.js 版本不足，安装流程会先自动补齐再继续。
- **快照恢复更顺手**：快照导入改为 Android 文件选择器；安装完成页新增“导入快照”按钮，恢复已有配置更直接。
- **快照导出体验优化**：快照导出支持先手动输入文件名，再保存到设备目录。
- **网关日志持久化与轮转**：新增可选的网关日志持久化开关，写入 `/root/openclaw.log`，单文件超过 5 MB 自动轮转，最多保留 3 份历史日志。
- **首页信息密度优化**：首页网关卡片排版细节优化，当前模型、版本和更新信息更紧凑，移动端查看更清晰。

## v1.8.8 - 仪表盘增强、配置编辑器与 OpenClaw 更新链路

### 关键改动

- **首页快捷操作重构**：新增首页 OpenClaw 版本显示，并支持检查更新、显示最新版本和直接更新。
- **OpenClaw 更新链路打通**：更新流程会自动检测 npm 最新 `openclaw` 版本与 Node.js 版本要求，不满足时自动升级内置 Node.js 后再更新 OpenClaw。
- **配置文件编辑器**：新增“修改配置文件”页面，可直接编辑 `openclaw.json`，支持 JSON 校验、格式化、保存和语法高亮。
- **常用命令入口**：新增“常用命令”页面，内置常见 OpenClaw 命令，支持一键复制。
- **日志查看增强**：日志页面支持切换查看“网关日志”和“对话日志”；对话日志读取 `/root/.openclaw/agents/main/sessions/` 下最新的 `.jsonl` 文件。
- **网关状态控制更明确**：网关按钮新增“启动中 / 停止中”状态；停止时会主动清理残留进程，减少“已经在运行”的误判。
- **自定义提供商配置修复**：修复自定义提供商配置后可能因 `gateway.mode` 未设置而导致网关启动失败的问题。
- **安装向导与元数据优化**：安装向导显示 OpenClaw 预计安装大小，作者名统一为 `JunWan`。

## v1.8.7 - 自定义 OpenAI、飞书消息平台与日志优化

### 关键改动

- **自定义 OpenAI 兼容提供商**：新增“自定义 OpenAI 兼容”AI 提供商，可填写 API 基础地址、API Key 与自定义模型名，方便接入各类兼容 OpenAI API 的服务。
- **网关日志可读性优化**：移除 ANSI 颜色控制符，统一显示为更直观的 `YYYY-MM-DD HH:mm:ss` 时间格式，并收敛部分 PRoot 启动 warning。
- **首页快捷操作调整**：将“AI 提供商”放在首位，并新增“接入消息平台”入口。
- **飞书消息平台接入**：新增飞书（Feishu）消息平台配置页，按照官方 `channels.feishu` 结构写入，并支持自动迁移旧的错误 `channels.lark` 配置。
- **飞书插件启用更省心**：飞书插件启用后，可在网关启动阶段自动完成插件启用与配置修正，减少手动执行 `doctor --fix` 的成本。

## v1.8.6 - 安装进度、日志工具与发布脚本

### 关键改动

- **安装进度反馈增强**：安装向导中的 RootFS 解压、基础包安装、Node.js 处理和 OpenClaw 安装阶段现在会显示更平滑的步骤百分比，减少长时间看起来“卡住不动”的情况。
- **日志工具补齐**：日志页面新增“清空日志”按钮，并带确认弹窗；该操作只会清空应用内日志列表，不会删除磁盘上的日志文件。
- **节点 WebSocket 心跳修复**：改为底层 ping 帧，不再发送纯文本 `ping`，从而避免网关侧的 JSON 解析错误。
- **PRoot 标准输入输出绑定优化**：仅在 `/proc/self/fd/0/1/2` 实际可绑定时才进行绑定，减少部分设备上的启动 warning。
- **发布打包脚本**：新增 Python 发布构建脚本，可交互输入版本号和构建号，并自动将 APK / AAB 整理到 `release/v1.8.6/` 目录。

## v1.8.5 - 汉化整合与仓库初始化

### 关键改动

- **中文整合版初始化**：本版本基于上游 `mithun50/openclaw-termux`，整合 `TIANLI0/openclaw-termux` 的 `feature/translation` 分支并做中文维护。
- **文档重构**：完成中文主文档重构，新增英文文档并支持中英文切换。
- **i18n 整合**：纳入简中、繁中、日文等多语言相关改动。
- **版本同步**：统一版本为 `v1.8.5`，同步 Changelog 与项目版本元数据。
- **包名调整**：修改 Android 包名为 `com.junwan666.openclawzh`，避免与上游官方英文版冲突，可与官方版本并存安装。

---

## v1.8.4 - Serial, Log Timestamps & ADB Backup

### New Features

- **Serial over Bluetooth & USB (#21)**: Added a `serial` node capability with 5 commands: `list`, `connect`, `disconnect`, `write`, `read`. Supports USB serial devices via `usb_serial` and BLE devices via Nordic UART Service (`flutter_blue_plus`). Device IDs are prefixed with `usb:` or `ble:` for disambiguation.
- **Gateway Log Timestamps (#54)**: All gateway log messages, both Kotlin and Dart side, now include ISO 8601 UTC timestamps for easier debugging.
- **ADB Backup Support (#55)**: Added `android:allowBackup="true"` to `AndroidManifest`, so users can back up app data via `adb backup`.

### Enhancements

- **Check for Updates (#59)**: Added a new "Check for Updates" option in Settings > About. It queries the GitHub Releases API, compares semver versions, and shows an update dialog with a download link if a newer release is available.

### Bug Fixes

- **Node Capabilities Not Available to AI (#56)**: `_writeNodeAllowConfig()` could silently fail when proot/node was not ready, causing the gateway to start without `allowCommands`. Added a direct file I/O fallback to write `openclaw.json` on the Android filesystem, and fixed `node.capabilities` to send both `commands` and `caps` fields.

### Node Command Reference Update

| Capability | Commands |
|------------|----------|
| Serial | `serial.list`, `serial.connect`, `serial.disconnect`, `serial.write`, `serial.read` |

---

## v1.8.3 - Multi-Instance Guard

### Bug Fixes

- **Duplicate Gateway Processes (#48)**: Services now guard against re-entry when Android re-delivers `onStartCommand` via `START_STICKY`, preventing duplicate processes, leaked wakelocks, and repeated answers to connected apps.
- **Wakelock Leaks**: All 5 foreground services release any existing wakelock before acquiring a new one.
- **Orphan PTY Instances**: Terminal, onboarding, configure, and package install screens now kill the previous PTY before starting a new one on retry.
- **Notification ID Collisions**: `SetupService` and `ScreenCaptureService` no longer share notification IDs with other services.

---

## v1.8.2 - DNS Reliability, Screenshot Capture, Custom Models & Setup Detection

### Bug Fixes

- **Setup State Detection (#44)**: `openclawx onboard` no longer says setup is incomplete after a successful setup. Replaced a slow proot exec check with a fast filesystem check plus a longer-timeout fallback.
- **DNS / No Internet Inside Proot (#45)**: `resolv.conf` is now written to both `config/resolv.conf` and `rootfs/ubuntu/etc/resolv.conf` at every entry point: app start, every proot invocation, gateway start, SSH start, and terminal screens.
- **NVIDIA NIM Config Breaks Onboarding (#46)**: Provider config save now falls back to direct file write if the proot Node.js one-liner fails, for example due to DNS issues.

### New Features

- **Screenshot Capture**: Terminal and log screens now have a camera button to capture the current view as a PNG image saved to device storage.
- **Custom Model Support (#46)**: AI Providers now allow entering any custom model name, such as `kimi-k2.5`, through a "Custom..." option in the model dropdown.
- **Updated NVIDIA Models (#46)**: Added `meta/llama-3.3-70b-instruct` and `deepseek-ai/deepseek-r1` to NVIDIA NIM default models.

### Reliability

- **resolv.conf at Every Entry Point**: `MainActivity.configureFlutterEngine()` ensures directories and `resolv.conf` exist on every app launch. `ProcessManager.ensureResolvConf()` guarantees it before every proot invocation. Kotlin services and Dart screens also have independent fallbacks.
- **APK Update Resilience**: Directories and DNS config are recreated on engine init, so the app recovers automatically after an APK update clears `filesDir`.

---

## v1.8.0 - AI Providers, SSH Access, Ctrl Keys & Configure Menu

### New Features

- **AI Providers**: Added an "AI Providers" screen to configure API keys and select models for 7 providers: Anthropic, OpenAI, Google Gemini, OpenRouter, NVIDIA NIM, DeepSeek, and xAI. Writes configuration directly to `~/.openclaw/openclaw.json`.
- **SSH Remote Access**: Added an "SSH Access" screen to start or stop an SSH server (`sshd`) inside proot, set the root password, and view copyable `ssh` commands.
- **Configure Menu**: Added a "Configure" dashboard card that opens `openclaw configure` in a built-in terminal.
- **Clickable URLs**: Terminal and onboarding screens now detect tapped URLs and offer Open / Copy / Cancel actions.

### Bug Fixes

- **Ctrl Key with Soft Keyboard (#37)**: Ctrl and Alt modifier state from the toolbar now applies to soft keyboard input across terminal-related screens.
- **Ctrl+Arrow/Home/End/PgUp/PgDn (#38)**: Toolbar Ctrl modifier now sends correct escape sequences for arrow keys and navigation keys.
- **resolv.conf ENOENT after Update (#40)**: DNS resolution failures caused by missing `resolv.conf` are now handled on app launch, before every proot operation, and during gateway service init.

### Dashboard

- Added "AI Providers" and "SSH Access" quick action cards.

---

## v1.7.3 - DNS Fix, Snapshot & Version Sync

### Bug Fixes

- **DNS Breaks After a While (#34)**: `resolv.conf` is now written before every gateway start in both the Flutter layer and the Android foreground service, not just during initial setup.
- **Version Mismatch (#35)**: Synced version strings across `constants.dart`, `pubspec.yaml`, `package.json`, and `lib/index.js` so they all report `1.7.3`.

### New Features

- **Config Snapshot (#27)**: Added Export / Import Snapshot buttons under Settings > Maintenance. Export saves `openclaw.json` and app preferences to a JSON file, and Import restores them. A "Snapshot" quick action card was also added to the dashboard.
- **Storage Access**: Added Termux-style "Setup Storage" in Settings. Grants shared storage permission and bind-mounts `/sdcard` into proot, so files in `/sdcard/Download` and similar directories are accessible inside the Ubuntu environment.

---

## v1.7.2 - Setup Fix

### Bug Fixes

- **node-gyp Python Error**: Fixed `PlatformException(PROOT_ERROR)` during setup caused by npm's bundled `node-gyp` failing to find Python. The rootfs now installs `python3`, `make`, and `g++`.
- **tzdata Interactive Prompt**: Fixed setup hanging on continent or timezone selection by pre-configuring timezone to UTC before installing `python3`.
- **proot-compat Spawn Mock**: Removed `node-gyp` and `make` from the mocked side-effect command list since real build tools are now installed.

---

## v1.7.1 - Background Persistence & Camera Fix

> Requires Android 10+ (API 29)

### Node Background Persistence

- **Lifecycle-Aware Reconnection**: Handles both `resumed` and `paused` lifecycle states, and forces a connection health check on app resume since Dart timers freeze while backgrounded.
- **Foreground Service Verification**: Watchdog, resume handler, and pause handler all verify the Android foreground service is still alive and restart it if killed.
- **Stale Connection Recovery**: On app resume, detects stale WebSocket connections and forces a full reconnect instead of silently staying in a paired state.
- **Live Notification Status**: Foreground notification text updates in real time to reflect node state.

### Camera Fix

- **Immediate Camera Release**: Camera hardware is released immediately after each snap or clip using `try/finally`, preventing repeated capture errors.
- **Auto-Exposure Settle**: Added a 500 ms settle time before snap for proper auto-exposure and focus.
- **Flash Conflict Prevention**: Flash capability releases the camera when torch is turned off so later snap or clip operations do not conflict.
- **Stale Controller Recovery**: Flash capability detects errored or stale controllers and recreates them instead of failing silently.

---

## v1.7.0 - Clean Modern UI Redesign

> Requires Android 10+ (API 29)

### UI Overhaul

- **New Color System**: Replaced default Material 3 purple with a black-and-white palette plus red (`#DC2626`) accent, inspired by Linear and Vercel.
- **Inter Typography**: Added Google Fonts Inter across the app for a cleaner modern feel.
- **AppColors Class**: Centralized color constants for consistent theming.
- **Dark Mode**: Near-black backgrounds, subtle surfaces, and bordered cards.
- **Light Mode**: Clean white backgrounds and light bordered cards.

### Component Redesign

- **Zero-Elevation Cards**: Cards now use 1 px borders with 12 px radius instead of drop shadows.
- **Pill Status Badges**: Gateway and Node controls show icon-plus-label status badges instead of small dots.
- **Monochrome Dashboard**: Removed rainbow icon colors from quick action cards in favor of neutral muted tones.
- **Uppercase Section Headers**: Settings, Node, and Setup screens use letter-spaced muted headers.
- **Red Accent Buttons**: Primary actions use red filled buttons, while destructive and secondary actions use outlined styles.
- **Terminal Toolbar**: Aligned toolbar colors to the new palette and improved active modifier styling.

### Splash Screen

- **Fade-In Animation**: Added an 800 ms fade-in on launch.
- **App Icon Branding**: Uses `ic_launcher.png` instead of the generic cloud icon.
- **Inter Bold Wordmark**: "OpenClaw" now uses Inter weight 800 with letter spacing.

### Polish

- **Log Colors**: INFO lines use muted grey instead of red, WARN uses amber.
- **Installed Badges**: Package screens use a consistent green (`#22C55E`) for "Installed" badges.
- **Capability Icons**: Node screen capability icons use muted colors instead of primary red.
- **Input Focus**: Text fields highlight with a red border on focus.
- **Switches**: Red thumb when active, grey when inactive.
- **Progress Indicators**: All progress indicators use the red accent color.

### CI

- Removed OpenClaw Node app build from workflow and kept gateway-only CI.

---

## v1.6.1 - Node Capabilities & Background Resilience

> Requires Android 10+ (API 29)

### New Features

- **7 Node Capabilities (15 commands)**: Camera, Flash, Location, Screen, Sensor, Haptic, and Canvas are fully registered and exposed to the AI through the WebSocket node protocol.
- **Proactive Permission Requests**: Camera, location, and sensor permissions are requested up front when the node is enabled.
- **Battery Optimization Prompt**: The app can ask users to exempt it from battery restrictions when enabling the node.

### Background Resilience

- **WebSocket Keep-Alive**: Added a 30-second periodic ping to prevent idle timeout.
- **Connection Watchdog**: Added a 45-second timer to detect dropped connections and trigger reconnects.
- **Stale Connection Detection**: Forces reconnect if no data is received for 90 seconds or more.
- **App Lifecycle Handling**: Auto-reconnects node when the app returns to the foreground.
- **Exponential Backoff**: Reconnect attempts now use 350 ms to 8 s backoff to avoid flooding.

### Fixes

- **Gateway Config**: Patches `/root/.openclaw/openclaw.json` to clear `denyCommands` and set `allowCommands` for all 15 commands.
- **Location Timeout**: Added a 10-second time limit to GPS fix with fallback to the last known position.
- **Canvas Errors**: Returns honest `NOT_IMPLEMENTED` errors instead of fake success responses.
- **Node Display Name**: Renamed from "OpenClaw Termux" to "OpenClawX Node".

### Node Command Reference

| Capability | Commands |
|------------|----------|
| Camera | `camera.snap`, `camera.clip`, `camera.list` |
| Canvas | `canvas.navigate`, `canvas.eval`, `canvas.snapshot` |
| Flash | `flash.on`, `flash.off`, `flash.toggle`, `flash.status` |
| Location | `location.get` |
| Screen | `screen.record` |
| Sensor | `sensor.read`, `sensor.list` |
| Haptic | `haptic.vibrate` |

---

## v1.5.5

- Initial release with gateway management, terminal emulator, and basic node support.
