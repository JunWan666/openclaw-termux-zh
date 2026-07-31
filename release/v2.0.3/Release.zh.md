# OpenClaw Android 中文版 v2.0.3

独立 Android 应用，无需单独安装 Termux。本次 v2.0.3 重点完善 OpenClaw 新旧版本兼容、环境恢复、升级保护和 AI 提供商配置，Android 构建号为 `78`。

## 本次更新

- 固定 `2026.3.23` 为默认 Stable，在线获取的 npm `latest` 作为 Experimental；保留 `2026.3.13` 及之后的历史版本，更早版本不再出现在版本选择中。
- 为 `2026.3.13` 与 `2026.3.23` 保留“推荐”标记；支持完整 Node.js `engines` 范围解析，安装前会选择经过验证且真正满足要求的 Node.js 运行时。
- 新增 Gateway v3/v4 兼容层，覆盖握手、Token、deviceToken、scope、重试建议和安全协议降级；鉴权错误不会被误判成协议问题。
- 启动时区分全新环境、完整环境、可自动修复、升级中断和需要人工恢复；自动修复只重建 wrapper、PRoot compatibility、Bionic Bypass 和 DNS 等运行文件，不删除 RootFS 与用户数据。
- OpenClaw 升级和降级增加保护事务、配置脱敏差异、doctor 检查与失败回滚，避免中断后留下半升级状态。
- `2026.3.13` 及之后版本使用最小基础配置跳过终端交互，安装完成后直接进入首页配置 API。
- AI 提供商重新排序：DeepSeek、英伟达（NVIDIA 免费）、智谱靠前展示；删除 OpenRouter 与 xAI，并更新 DeepSeek/NVIDIA 模型、Key 获取入口、模型列表拉取和连接测试。
- “自定义模型提供商”更名为“自定义 OpenAI 兼容模型”；填写 Base URL 与 API Key 后可自动拉取 `/models`，也可手动刷新、下拉选择或继续填写自定义模型 ID。
- 自定义 Provider Base URL 保存时不再自动追加 `/v1`，测试和模型列表请求只在实际调用时拼接对应 endpoint。
- Gateway 冷启动支持取消并清理同 UID 的残留 PRoot/OpenClaw 进程，减少启动失败后后台残留。
- 完整测试集共 119 项通过，覆盖版本策略、Gateway 协议、环境恢复、升级保护、Provider 配置和模型目录。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v2.0.3-universal.apk` | 不确定架构时优先下载 | 46.78 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-universal.apk) |
| `OpenClaw-v2.0.3-arm64-v8a.apk` | 大多数现代 Android 手机 | 27.96 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-arm64-v8a.apk) |
| `OpenClaw-v2.0.3-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 27.70 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-armeabi-v7a.apk) |
| `OpenClaw-v2.0.3-x86_64.apk` | 模拟器或 x86_64 设备 | 28.19 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-x86_64.apk) |
| `OpenClaw-v2.0.3.aab` | 应用商店分发 | 67.03 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3.aab) |

## 升级提示

1. 本次版本使用 Android 构建号 `78`，可覆盖安装 v2.0.2 及此前正式包。
2. 升级或切换 OpenClaw 版本前建议先通过备份中心保存配置或工作目录；新升级事务会尽量保护用户数据，但跨版本降级仍可能遇到上游配置字段差异。
3. 现有完整环境会直接复用；检测到 wrapper、Bionic Bypass、PRoot compatibility 或 DNS 等可恢复文件缺失时，App 会先尝试自动修复。
4. `2026.3.23` 继续作为推荐稳定版本；Experimental 适合测试新能力，不建议在重要环境中直接替换 Stable。
5. ARMv7 设备受已验证 Node.js 版本限制，部分较新的 Experimental OpenClaw 版本可能不会提供安装入口。
6. 自定义 OpenAI 兼容服务如果不提供 `/models`，仍可手工填写模型 ID 后进行连接测试和保存。

## 首次运行

1. 安装与设备架构匹配的 APK；不确定时可使用 Universal APK。
2. 首次进入安装页后选择 OpenClaw 版本，默认推荐 `2026.3.23`。
3. 按向导完成 Ubuntu RootFS、Node.js 与 OpenClaw 初始化；`2026.3.13` 及之后版本会自动创建最小配置，不再要求完成终端式 Onboarding。
4. 初始化完成后进入首页，在“AI 提供商”中填写 API Key、选择模型并测试连接。
5. 启动 Gateway，点击首页地址打开 Web 控制台。

## 文件校验（SHA256）

- `OpenClaw-v2.0.3-universal.apk`: `C3009FD01007F0C1D3D58AB381F03FAC295A3B9EAF1583DAF109C1C6815F05EE`
- `OpenClaw-v2.0.3-arm64-v8a.apk`: `E57994672AE9270FF0B8C8FFB3388A4C8F09D37DF651F953956997B8C2ADFBCB`
- `OpenClaw-v2.0.3-armeabi-v7a.apk`: `B49C6FF5836EB7E2C750C610DBA99B32328A7671C9CFFD6A276786B0286F9CC2`
- `OpenClaw-v2.0.3-x86_64.apk`: `77E9A7528BAD2F064A803624F9D7CA5C2900CCF535D2013789ED4D624AE93363`
- `OpenClaw-v2.0.3.aab`: `AD04709932900649C36DBE4E3BC5CF7F5FC0F8A9EB8BAE4B9C3F7C5B0CBE4810`
