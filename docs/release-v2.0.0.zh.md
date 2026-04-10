# OpenClaw Android 中文版 v2.0.0

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 初始化完成后点击“配置 API”时，如果当前 OpenClaw 版本命中内置示例配置，会弹窗提示是否直接套用；目前内置 `2026.3.13`、`2026.3.23`、`2026.4.9` 三套示例，可跳过终端引导直接进入首页。
- 初始化和首页版本选择默认更推荐 `2026.3.23`，并为 `2026.3.13`、`2026.3.23` 标记“推荐”；安装链路继续保留详细日志、下载进度、速度与 ETA，并默认关闭 npm 的 audit/fund/progress 额外开销。
- 对话日志页面改为气泡时间线展示，支持自动刷新、自动滚动、“跳到最新”按钮与日志复制，查看最新会话更顺手。
- “常用命令”升级为支持 Markdown 的“常用说明”，代码块、浏览器地址和提示词都带复制按钮，并新增“如何进行局域网访问”完整教程。
- 配置编辑器针对手机键盘遮挡做了紧凑化处理；节点页新增独立配置入口、日志复制按钮，并将 `Canvas` 明确标记为暂不可用。
- 内嵌 Web Dashboard 增强了空白页探测、地址回退、外部浏览器打开、自适应缩放与倍率记忆，尽量贴近手机浏览器体验。
- README 与文档资源重构为正式发布形态，补充了截图、架构图、节点能力说明、重要警告和 Star History。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v2.0.0-universal.apk` | 不确定架构时优先下载 | 101.26 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.0/OpenClaw-v2.0.0-universal.apk) |
| `OpenClaw-v2.0.0-arm64-v8a.apk` | 大多数现代 Android 手机 | 83.53 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.0/OpenClaw-v2.0.0-arm64-v8a.apk) |
| `OpenClaw-v2.0.0-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 83.23 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.0/OpenClaw-v2.0.0-armeabi-v7a.apk) |
| `OpenClaw-v2.0.0-x86_64.apk` | 模拟器或 x86_64 设备 | 83.74 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.0/OpenClaw-v2.0.0-x86_64.apk) |
| `OpenClaw-v2.0.0.aab` | 应用商店分发 | 108.05 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.0/OpenClaw-v2.0.0.aab) |

## 升级提示

1. 本次正式版使用 Android 构建号 `54`，可以覆盖此前测试的 `2.0.x` 安装包。
2. 如果希望快速完成 API 配置，可在初始化完成后点击“配置 API”，优先尝试是否有命中的内置示例配置。
3. 套用内置示例配置后，请务必进入“AI 提供商”，把 Base URL、API Key 与模型改成你自己的，再启动 Gateway。
4. 如果内嵌 Web Dashboard 在你的系统 WebView 中仍有适配问题，可以先用页面右上角按钮切到外部浏览器继续操作。
5. 节点页中的 `Canvas` 目前仍是规划能力，README 会展示能力规划，但这项功能现在不能按可用能力使用。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，确认目标 OpenClaw 版本，默认建议优先选择带“推荐”标记的版本。
3. 按向导完成 Ubuntu RootFS、基础包、Node.js 24 与 OpenClaw 的初始化。
4. 完成后点击“配置 API”；如果弹出内置示例配置提示，可按需选择“使用示例配置”或继续终端引导。
5. 如使用示例配置，进入首页后先到“AI 提供商”中替换成自己的 API 信息。
6. 启动 Gateway，并点击首页地址打开 Web 控制台。

## 文件校验（SHA256）

- `OpenClaw-v2.0.0-universal.apk`: `BD6B0E954DE0E90AADA87EC323F5D52C5A52941AC85ECA52488769097ADBAB4D`
- `OpenClaw-v2.0.0-arm64-v8a.apk`: `C573857DF7ED386FB1778CB5B8D3B13F425B1C33A8078C507FC8341DE8A94B24`
- `OpenClaw-v2.0.0-armeabi-v7a.apk`: `2A3955FEF40CC302887240DBDB10ED713C8A3514D141BC5C99C1E64F6268AE95`
- `OpenClaw-v2.0.0-x86_64.apk`: `D1E50B2EA8C9C604AADDFFBEE1DE222CA518D388952FBF2A97CF059B99163AD1`
- `OpenClaw-v2.0.0.aab`: `FF1BCB9DC3E8C69276DBC58A6BD6940522EAAAB3999B074960A84CE9AF715C3F`
