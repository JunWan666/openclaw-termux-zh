# Changelog

## v1.9.5 — 快照导出选位置与智谱 AI 适配

### 关键改动

- **快照导出改为系统保存面板**：设置页导出快照时不再固定写入应用私有目录或 `Download`，而是直接调用 Android 系统“创建文档”面板，由用户自己选择保存位置与文件名，备份文件更容易管理和查找。
- **原生桥接补齐导出链路**：Android 原生侧新增快照保存通道，能够把应用内生成的配置快照直接写入用户在系统文件选择器里指定的位置，并正确返回最终文件名。
- **智谱 AI 独立提供商适配**：AI 提供商列表新增 `智谱 AI`，内置官方基础地址 `https://open.bigmodel.cn/api/paas/v4` 和常用 `GLM` 模型预设，避免在自定义提供商里被错误补成 `/v1` 导致请求失败。
- **自定义提供商兼容检测增强**：自定义模型提供商新增 `智谱 AI Compatible` 兼容模式；连接测试、自动识别、已保存配置恢复和预设默认地址逻辑都同步适配 `bigmodel.cn`，并补充了对应测试覆盖。
- **多语言文案同步**：简中、繁中、英文、日文的智谱与快照相关提示文案已同步更新，保持不同语言界面下的配置体验一致。

## v1.9.4 — 首页控制台 Token URL 双重保险

### 关键改动

- **首页控制台地址补全更稳**：修复部分设备在安装完成或网关重启后，首页 URL 只显示 `http://127.0.0.1:18789`、没有自动带上 `#token=` 的问题。现在首页会优先从日志提取 token URL，并在缺失时主动向网关探测补全。
- **日志抓取兼容性增强**：不再只依赖 `localhost` / `127.0.0.1` 的固定格式，而是统一解析不同 host、query / fragment token 形式，以及部分响应体中的 token 信息，降低上游输出格式变化带来的影响。
- **启动时序降低漏抓概率**：启动网关时改为先订阅日志、再拉起网关进程，减少因为日志订阅晚于 token 输出而错过首条控制台地址的情况。
- **Node 侧 token 读取统一**：Node 连接网关时读取控制台 token 的逻辑也切到统一解析器，避免首页拿到 token、Node 侧却因旧正则过严再次取不到的情况。
- **CLI 版本号同步**：同步修正 `lib/index.js` 中落后的 CLI 版本号，避免仓库发布版本与 CLI 输出版本不一致。

## v1.9.3 — 应用内更新安装权限引导修复

### 关键改动

- **应用内更新安装链路修复**：修复更新包下载完成后直接跳回浏览器下载页的问题。现在应用会优先尝试调用 Android 系统安装器，而不是把已经下载好的 APK 重新交给浏览器处理。
- **未知来源安装权限引导补全**：当设备尚未允许 OpenClaw 安装未知应用时，应用会主动拉起系统授权页；授权返回后会继续执行安装流程，不需要用户手动重新查找安装包。
- **失败回退更准确**：Flutter 侧现在会区分“未授予安装权限”和“真正安装失败”两种情况。只有在应用内确实无法继续安装时，才会回退到浏览器下载页，并给出更明确的提示。
- **多语言提示同步**：同步补充简体中文、繁体中文、英文、日文的安装失败提示文案，避免不同语言界面下的更新反馈不一致。

## v1.9.2 — 首页更新提醒按钮与统一更新入口

### 关键改动

- **首页更新提醒更直观**：在首页左上角 `OpenClaw` 标题右侧新增轻量化的检查更新按钮，默认保持低存在感；当检测到新版本时，会切换成更明显的更新图标并附带红点提示，方便第一时间注意到可升级状态。
- **静默刷新更新状态**：首页会在首次进入、应用回到前台，以及从设置等页面返回后静默刷新版本状态，不需要反复手动进入设置页才能知道是否有新版本。
- **更新流程入口统一**：首页标题按钮和设置页“检查更新”现在复用同一套弹窗、下载、安装与失败回退逻辑，避免两个入口行为不一致。

## v1.9.1 — QQ / 微信接入与应用内更新安装

### 关键改动

- **QQ 机器人接入**：消息平台页新增 QQ 机器人入口。进入页面时会自动检测并安装 `@tencent-connect/openclaw-qqbot@latest` 插件，可直接打开腾讯 QQ Bot 接入页；保存时会执行 `openclaw channels add --channel qqbot --token "<AppID>:<AppSecret>"` 完成绑定，并在完成后提示重启网关。
- **微信接入引导**：新增微信接入入口与独立安装终端页，可检测 `@tencent/openclaw-weixin` 插件状态；未安装时可一键启动 `npx -y @tencent-weixin/openclaw-weixin-cli install`，在终端中查看二维码或登录链接完成绑定，也支持重新打开终端继续处理。
- **应用内更新下载与安装**：检查更新现在会解析 GitHub Release 的全部资产，根据设备架构自动优先选择对应 APK，应用内完成下载后直接调用 Android 系统安装器；如果下载或安装失败，会自动回退到浏览器打开对应下载页。
- **Android 安装桥接完善**：新增 `FileProvider` 和安装包调用通道，补充 `REQUEST_INSTALL_PACKAGES` 权限，并为 ABI 资产选择增加测试覆盖，提升更新链路稳定性。

## v1.9.0 — 自定义兼容提供商、API 检测与安装引导权限修正

### 关键改动

- **自定义兼容提供商扩展**：新增独立的自定义提供商详情页，可保存多个自定义预设，并支持 OpenAI Chat Completions、OpenAI Responses、Anthropic Messages、Google Generative AI 四类兼容模式以及自动识别，适合接入更多第三方模型网关。
- **保存前连接检测**：自定义提供商新增“测试连接”能力；保存时会优先复用最近一次检测结果，若尚未检测或检测失败，会先主动探测 API 是否可用，并在失败时展示原因，再由用户确认是否继续保存。
- **首页版本状态提示更清晰**：网关卡片的版本区域改为围绕已选版本展示，最新版只作为候选版本提示；当检测到新版本时，会更明确地显示“可更新”，减少“当前最新”表述带来的误导。
- **安装引导导入快照更克制**：首次安装完成页仍可直接导入快照恢复配置，但安装引导场景下恢复快照时不再自动重新启用 Node，避免因为旧快照中的 `nodeEnabled` 配置触发相机、定位、传感器、蓝牙等整套权限申请。
- **仓库发布元数据同步**：应用内作者信息、GitHub 链接、版本检查接口与 CLI 版本号已经统一对齐到本仓库的 1.9.0 发布链路，后续发布与更新提示会更一致。

## v1.8.9 — 可选 OpenClaw 版本、快照恢复提速与网关日志轮转

### 关键改动

- **OpenClaw 版本选择**：安装首页与首页网关卡片都支持拉取 npm 已发布的 `openclaw` 版本列表，默认选中最新版本，也可以手动选择指定版本执行安装、重装、升级或降级，方便在上游某个最新版临时异常时快速切换。
- **版本安装链路增强**：选择具体 OpenClaw 版本时，会同步展示对应的预计安装体积与 Node.js 要求；安装流程和首页手动安装都会先校验内置 Node.js 版本，不满足要求时自动升级后再继续。
- **快照恢复更顺手**：快照导入改为 Android 文件选择器，不再依赖手动填写路径；安装完成页新增“导入快照”按钮，可在不重新配置 API Key 的情况下更快恢复已有配置。
- **快照导出体验优化**：导出快照时支持先输入文件名再保存，便于按用途或设备手动命名备份文件。
- **网关日志持久化与轮转**：设置页新增可选的网关日志持久化开关；启用后会写入 `/root/openclaw.log`，单文件超过 5 MB 自动轮转为历史文件，最多保留 3 份。
- **首页信息细节调整**：首页网关卡片保留当前模型展示，并对版本/更新区域的字号与间距做了收紧，信息密度更高，移动端查看更清晰。

## v1.8.8 — 仪表盘增强、配置编辑器与 OpenClaw 更新链路

### 关键改动

- **首页快捷操作重构**：隐藏“引导配置”和“Web 控制台”卡片，新增“修改配置文件”和“常用命令”入口；网关区域新增当前 OpenClaw 版本显示，首页信息更集中。
- **OpenClaw 版本检测与一键更新**：网关卡片新增“检查更新 / 更新 / 最新”状态按钮；会先查询 npm 最新 `openclaw` 版本，再自动检测 Node.js 版本要求，不满足时先升级内置 Node.js，再执行 `openclaw@latest` 安装。
- **配置文件编辑器**：新增内置 `openclaw.json` 编辑页，支持 JSON 校验、格式化、保存，并加入 JSON 语法高亮，便于直接区分键、值、布尔值和数字。
- **常用命令入口**：新增常用命令页，内置 `openclaw onboard --install-daemon`、`openclaw config set tools.profile full`、`openclaw configure` 三条命令，并支持一键复制。
- **日志增强**：日志页现在可切换查看“网关日志”和“对话日志”；对话日志会读取 `/root/.openclaw/agents/main/sessions/` 下最新的 `.jsonl` 会话文件。
- **网关启动 / 停止可靠性**：新增“启动中 / 停止中”状态展示；停止网关时会主动清理残留进程，避免再次启动时误报“已在运行”。
- **自定义提供商配置修复**：写入自定义提供商配置时会自动补齐 `gateway.mode=local`，修复因模式未设置导致网关启动被阻止的问题。
- **安装向导与版本细节优化**：安装页增加 OpenClaw 预计安装大小显示，作者信息统一为 `JunWan`；安装与更新默认使用 `openclaw@latest`，并同步将默认 Node.js 版本提升到 `22.16.0` 以满足当前上游要求。
- **移动端 Web 页面查看优化**：应用内打开网关地址时，默认以更适合手机查看的缩放方式展示 OpenClaw Web 页面。

## v1.8.7 — 自定义 OpenAI、日志优化与飞书消息平台

### 关键改动

- **自定义 OpenAI 兼容提供商**：AI 提供商页新增“自定义 OpenAI 兼容”入口，可填写 API 基础地址、API Key 和任意模型名；基础地址会自动补全到 `/v1`，方便接入各类 OpenAI-Compatible 服务。
- **网关日志可读性优化**：应用内日志统一清理 ANSI 颜色转义序列，并格式化为 `YYYY-MM-DD HH:mm:ss` 时间戳；同时减少部分 Android 场景下 `can't sanitize binding "/proc/self/fd/*"` 这类 PRoot warning 的干扰。
- **快捷操作重排**：仪表盘将“AI 提供商”移动到快捷操作首位，便于首次配置；并新增“接入消息平台”入口，提升配置路径的一致性。
- **消息平台接入页**：新增“接入消息平台”页面，并提供首个飞书 / Feishu 配置入口，界面风格与 AI 提供商页保持一致。
- **飞书官方配置结构适配**：飞书配置现按官方 `channels.feishu.defaultAccount + accounts.default` 结构写入 `openclaw.json`；网关启动前会自动迁移旧的错误 `channels.lark` 配置，避免因 schema 不兼容导致启动失败。

## v1.8.6 — 安装进度、日志工具与发布脚本

### 关键改动

- **安装进度反馈**：优化安装向导的进度显示。RootFS 解压、基础包安装、Node.js 处理和 OpenClaw 安装等长耗时阶段现在会显示更平滑的步骤百分比，减少长时间看起来“卡住不动”的情况；临时加入的总进度卡片也已移除，仅保留每个步骤自己的百分比显示。
- **网关日志工具**：日志查看页新增“清空日志”按钮，并带确认弹窗；该操作只会清空应用内的日志列表，不会删除磁盘上的日志文件。
- **节点 WebSocket 心跳修复**：节点 WebSocket 心跳从发送文本 `ping` 改为使用底层 ping 帧，避免网关出现 `Unexpected token 'p', "ping" is not valid JSON` 这类 JSON 解析错误。
- **PRoot 启动警告收敛**：现在只有在宿主端标准输入输出句柄确实可绑定时，才会绑定 `/proc/self/fd/0/1/2`，从而减少部分 Android 前台服务场景下网关启动时的 `can't sanitize binding "/proc/self/fd/*"` warning。
- **发布打包流程**：新增 `scripts/build_release.py` 发布构建脚本，可交互输入发布版本和构建号，默认将构建号设为当前 `pubspec` 的下一个值，并可自动准备 PRoot 二进制、整理 APK/AAB 到 `release/v版本/` 目录；README 也已补充对应说明。

## v1.8.5 — i18n Integration / 汉化整合

### Key Changes / 关键改动

- **Branch Integration / 分支整合**: Merged translation branch `pr-68` onto latest upstream `main` in commit `65a4a8b`, so this release contains both upstream fixes and i18n updates.
- **Localization Core / 本地化核心**: Added localization entrypoint and string bundles at `flutter_app/lib/l10n/app_localizations.dart`, `flutter_app/lib/l10n/app_strings_en.dart`, `flutter_app/lib/l10n/app_strings_zh_hans.dart`, `flutter_app/lib/l10n/app_strings_zh_hant.dart`, and `flutter_app/lib/l10n/app_strings_ja.dart`.
- **Locale State Management / 语言状态管理**: Added persistent locale provider `flutter_app/lib/providers/locale_provider.dart`; app language can be switched and remembered across restarts.
- **UI Coverage Expansion / 界面覆盖扩展**: Localized major screens including dashboard, settings, setup wizard, providers, logs, onboarding, and packages in `flutter_app/lib/screens/*`.
- **Provider Metadata Updates / Provider 元数据更新**: Updated provider model metadata and provider configuration flow in `flutter_app/lib/models/ai_provider.dart` and `flutter_app/lib/services/provider_config_service.dart`, including localized provider-related labels.
- **App Wiring / 应用接线**: Updated app bootstrap wiring in `flutter_app/lib/app.dart` and settings/preferences handling in `flutter_app/lib/services/preferences_service.dart` to ensure locale initialization and usage is consistent.
- **Tooling / 工具脚本**: Added helper script `flutter_app/scripts/_expand_l10n.dart` for localization text processing workflow.

## v1.8.4 — Serial, Log Timestamps & ADB Backup

### New Features

- **Serial over Bluetooth & USB (#21)** — New `serial` node capability with 5 commands (`list`, `connect`, `disconnect`, `write`, `read`). Supports USB serial devices via `usb_serial` and BLE devices via Nordic UART Service (flutter_blue_plus). Device IDs prefixed with `usb:` or `ble:` for disambiguation
- **Gateway Log Timestamps (#54)** — All gateway log messages (both Kotlin and Dart side) now include ISO 8601 UTC timestamps for easier debugging
- **ADB Backup Support (#55)** — Added `android:allowBackup="true"` to AndroidManifest so users can back up app data via `adb backup`

### Enhancements

- **Check for Updates (#59)** — New "Check for Updates" option in Settings > About. Queries the GitHub Releases API, compares semver versions, and shows an update dialog with a download link if a newer release is available

### Bug Fixes

- **Node Capabilities Not Available to AI (#56)** — `_writeNodeAllowConfig()` silently failed when proot/node wasn't ready, causing the gateway to start with no `allowCommands`. Added direct file I/O fallback to write `openclaw.json` directly on the Android filesystem. Also fixed `node.capabilities` event to send both `commands` and `caps` fields matching the connect frame format

### Node Command Reference Update

| Capability | Commands |
|------------|----------|
| Serial | `serial.list`, `serial.connect`, `serial.disconnect`, `serial.write`, `serial.read` |

---

## v1.8.3 — Multi-Instance Guard

### Bug Fixes

- **Duplicate Gateway Processes (#48)** — Services now guard against re-entry when Android re-delivers `onStartCommand` via `START_STICKY`, preventing duplicate processes, leaked wakelocks, and repeated answers to connected apps
- **Wakelock Leaks** — All 5 foreground services release any existing wakelock before acquiring a new one
- **Orphan PTY Instances** — Terminal, onboarding, configure, and package install screens now kill the previous PTY before starting a new one on retry
- **Notification ID Collisions** — SetupService and ScreenCaptureService no longer share notification IDs with other services

---

## v1.8.2 — DNS Reliability, Screenshot Capture, Custom Models & Setup Detection

### Bug Fixes

- **Setup State Detection (#44)** — `openclawx onboard` no longer says setup isn't done after a successful setup. Replaced slow proot exec check with fast filesystem check for openclaw detection, with a longer-timeout fallback
- **DNS / No Internet Inside Proot (#45)** — resolv.conf is now written to both `config/resolv.conf` (bind-mount source) and `rootfs/ubuntu/etc/resolv.conf` (direct fallback) at every entry point: app start, every proot invocation, gateway start, SSH start, and all terminal screens. Survives APK updates
- **NVIDIA NIM Config Breaks Onboarding (#46)** — Provider config save now falls back to direct file write if the proot Node.js one-liner fails (e.g. due to DNS issues)

### New Features

- **Screenshot Capture** — All terminal and log screens now have a camera button to capture the current view as a PNG image saved to device storage
- **Custom Model Support (#46)** — AI Providers screen now allows entering any custom model name (e.g. `kimi-k2.5`) via a "Custom..." option in the model dropdown
- **Updated NVIDIA Models (#46)** — Added `meta/llama-3.3-70b-instruct` and `deepseek-ai/deepseek-r1` to NVIDIA NIM default models

### Reliability

- **resolv.conf at Every Entry Point** — `MainActivity.configureFlutterEngine()` ensures directories and resolv.conf exist on every app launch. `ProcessManager.ensureResolvConf()` guarantees it before every proot invocation. All Kotlin services and Dart screens have independent fallbacks writing to both paths
- **APK Update Resilience** — Directories and DNS config are recreated on engine init, so the app recovers automatically after an APK update clears filesDir

---

## v1.8.0 — AI Providers, SSH Access, Ctrl Keys & Configure Menu

### New Features

- **AI Providers** — New "AI Providers" screen to configure API keys and select models for 7 providers: Anthropic, OpenAI, Google Gemini, OpenRouter, NVIDIA NIM, DeepSeek, and xAI. Writes configuration directly to `~/.openclaw/openclaw.json`
- **SSH Remote Access** — New "SSH Access" screen to start/stop an SSH server (sshd) inside proot, set the root password, and view connection info with copyable `ssh` commands. Runs as an Android foreground service for persistence
- **Configure Menu** — New "Configure" dashboard card opens `openclaw configure` in a built-in terminal for managing gateway settings
- **Clickable URLs** — Terminal and onboarding screens detect URLs at tap position (joining adjacent lines, stripping box-drawing characters) and offer Open/Copy/Cancel dialog

### Bug Fixes

- **Ctrl Key with Soft Keyboard (#37)** — Ctrl and Alt modifier state from the toolbar now applies to soft keyboard input across all terminal screens (terminal, configure, onboarding, package install). Previously only worked with toolbar buttons
- **Ctrl+Arrow/Home/End/PgUp/PgDn (#38)** — Toolbar Ctrl modifier now sends correct escape sequences for arrow keys and navigation keys (e.g. `Ctrl+Left` sends `ESC[1;5D`)
- **resolv.conf ENOENT after Update (#40)** — DNS resolution failed after app update because `resolv.conf` was missing. Now ensured on every app launch (splash screen), before every proot operation (`getProotShellConfig`), and in the gateway service init — covering reinstall, update, and normal launch

### Dashboard

- Added "AI Providers" and "SSH Access" quick action cards

---

## v1.7.3 — DNS Fix, Snapshot & Version Sync

### Bug Fixes

- **DNS Breaks After a While (#34)** — `resolv.conf` is now written before every gateway start (in both the Flutter service and the Android foreground service), not just during initial setup. This prevents DNS resolution failures when Android clears the app's file cache
- **Version Mismatch (#35)** — Synced version strings across `constants.dart`, `pubspec.yaml`, `package.json`, and `lib/index.js` so they all report `1.7.3`

### New Features

- **Config Snapshot (#27)** — Added Export/Import Snapshot buttons under Settings > Maintenance. Export saves `openclaw.json` and app preferences to a JSON file; Import restores them. A "Snapshot" quick action card is also available on the dashboard
- **Storage Access** — Added Termux-style "Setup Storage" in Settings. Grants shared storage permission and bind-mounts `/sdcard` into proot, so files in `/sdcard/Download` (etc.) are accessible from inside the Ubuntu environment. Snapshots are saved to `/sdcard/Download/` when permission is granted

---

## v1.7.2 — Setup Fix

### Bug Fixes

- **node-gyp Python Error** — Fixed `PlatformException(PROOT_ERROR)` during setup caused by npm's bundled node-gyp failing to find Python. Now installs `python3`, `make`, and `g++` in the rootfs so native addon compilation works properly
- **tzdata Interactive Prompt** — Fixed setup hanging on continent/timezone selection by pre-configuring timezone to UTC before installing python3
- **proot-compat Spawn Mock** — Removed `node-gyp` and `make` from the mocked side-effect command list since real build tools are now installed

---

## v1.7.1 — Background Persistence & Camera Fix

> Requires Android 10+ (API 29)

### Node Background Persistence

- **Lifecycle-Aware Reconnection** — Handles both `resumed` and `paused` lifecycle states; forces connection health check on app resume since Dart timers freeze while backgrounded
- **Foreground Service Verification** — Watchdog, resume handler, and pause handler all verify the Android foreground service is still alive and restart it if killed
- **Stale Connection Recovery** — On app resume, detects if the WebSocket went stale (no data for 90s+) and forces a full reconnect instead of silently staying in "paired" state
- **Live Notification Status** — Foreground notification text updates in real-time to reflect node state (connected, connecting, reconnecting, error)

### Camera Fix

- **Immediate Camera Release** — Camera hardware is now released immediately after each snap/clip using `try/finally`, preventing "Failed to submit capture request" errors on repeated use
- **Auto-Exposure Settle** — Added 500ms settle time before snap for proper auto-exposure/focus
- **Flash Conflict Prevention** — Flash capability releases the camera when torch is turned off, so subsequent snap/clip operations don't conflict
- **Stale Controller Recovery** — Flash capability detects errored/stale controllers and recreates them instead of failing silently

---

## v1.7.0 — Clean Modern UI Redesign

> Requires Android 10+ (API 29)

### UI Overhaul

- **New Color System** — Replaced default Material 3 purple with a professional black/white palette and red (#DC2626) accent, inspired by Linear/Vercel design language
- **Inter Typography** — Added Google Fonts Inter across the entire app for a clean, modern feel
- **AppColors Class** — Centralized color constants for consistent theming (dark bg, surfaces, borders, status colors)
- **Dark Mode** — Near-black backgrounds (#0A0A0A), subtle surface (#121212), bordered cards
- **Light Mode** — Clean white backgrounds, light borders (#E5E5E5), bordered cards

### Component Redesign

- **Zero-Elevation Cards** — All cards now use 1px borders with 12px radius instead of drop shadows
- **Pill Status Badges** — Gateway and Node controls show pill-shaped badges (icon + label) instead of 12px status dots
- **Monochrome Dashboard** — Removed rainbow icon colors from quick action cards; all icons use neutral muted tones
- **Uppercase Section Headers** — Settings, Node, and Setup screens use letterspaced muted grey headers
- **Red Accent Buttons** — Primary actions (Start Gateway, Enable Node, Install) use red filled buttons; destructive/secondary actions use outlined buttons
- **Terminal Toolbar** — Aligned colors to new palette; CTRL/ALT active state uses red accent; bumped border radius

### Splash Screen

- **Fade-In Animation** — 800ms fade-in on launch with easeOut curve
- **App Icon Branding** — Uses ic_launcher.png instead of generic cloud icon
- **Inter Bold Wordmark** — "OpenClaw" displayed in Inter weight 800 with letter-spacing

### Polish

- **Log Colors** — INFO lines use muted grey (not red); WARN uses amber instead of orange
- **Installed Badges** — Package screens use consistent green (#22C55E) for "Installed" badges
- **Capability Icons** — Node screen capabilities use muted color instead of primary red
- **Input Focus** — Text fields highlight with red border on focus
- **Switches** — Red thumb when active, grey when inactive
- **Progress Indicators** — All use red accent color

### CI

- Removed OpenClaw Node app build from workflow (gateway-only CI now)

---

## v1.6.1 — Node Capabilities & Background Resilience

> Requires Android 10+ (API 29)

### New Features

- **7 Node Capabilities (15 commands)** — Camera, Flash, Location, Screen, Sensor, Haptic, and Canvas now fully registered and exposed to the AI via WebSocket node protocol
- **Proactive Permission Requests** — Camera, location, and sensor permissions are requested upfront when the node is enabled, before the gateway sends invoke requests
- **Battery Optimization Prompt** — Automatically asks user to exempt the app from battery restrictions when enabling the node

### Background Resilience

- **WebSocket Keep-Alive** — 30-second periodic ping prevents idle connection timeout
- **Connection Watchdog** — 45-second timer detects dropped connections and triggers reconnect
- **Stale Connection Detection** — Forces reconnect if no data received for 90+ seconds
- **App Lifecycle Handling** — Auto-reconnects node when app returns to foreground after being backgrounded
- **Exponential Backoff** — Reconnect attempts use 350ms-8s backoff to avoid flooding

### Fixes

- **Gateway Config** — Patches `/root/.openclaw/openclaw.json` to clear `denyCommands` and set `allowCommands` for all 15 commands (previously wrote to wrong config file)
- **Location Timeout** — Added 10-second time limit to GPS fix with fallback to last known position
- **Canvas Errors** — Returns honest `NOT_IMPLEMENTED` errors instead of fake success responses
- **Node Display Name** — Renamed from "OpenClaw Termux" to "OpenClawX Node"

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

- Initial release with gateway management, terminal emulator, and basic node support
