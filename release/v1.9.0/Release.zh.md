# OpenClaw Android 中文版 v1.9.0

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 新增独立的自定义兼容提供商配置页，可保存多个预设，并支持 OpenAI Chat Completions、OpenAI Responses、Anthropic Messages、Google Generative AI 兼容模式与自动识别。
- 自定义提供商新增“测试连接”与保存前自动检测；当 API 不可用时会展示失败原因，并由你决定是否继续保存。
- 首页网关卡片的版本状态提示已重构，当前展示更偏向“已选版本 + 是否可更新”，减少“当前最新”表述带来的误导。
- 安装引导完成页仍支持直接导入快照；但在安装引导场景恢复快照时，不再自动重新启用 Node，避免旧快照触发整套 Node 权限申请。
- 应用内 GitHub 链接、版本检查来源与 CLI 版本号已统一对齐到本仓库的 1.9.0 发布链路。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.0-universal.apk` | 不确定架构时优先下载 | 43.72 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.0/OpenClaw-v1.9.0-universal.apk) |
| `OpenClaw-v1.9.0-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.90 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.0/OpenClaw-v1.9.0-arm64-v8a.apk) |
| `OpenClaw-v1.9.0-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.53 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.0/OpenClaw-v1.9.0-armeabi-v7a.apk) |
| `OpenClaw-v1.9.0-x86_64.apk` | 模拟器或 x86_64 设备 | 27.11 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.0/OpenClaw-v1.9.0-x86_64.apk) |
| `OpenClaw-v1.9.0.aab` | 应用商店分发 | 50.54 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.0/OpenClaw-v1.9.0.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.9.0`。
2. 如果你使用的是自定义兼容提供商，升级后建议进入对应预设执行一次“测试连接”，确认接口、模型名和兼容模式仍然可用。
3. 如果你在首次安装引导里导入了旧快照，Node 默认不会自动重新启用；确实需要节点能力时，可在设置页手动开启。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，可先选择目标 OpenClaw 版本，再点击“开始安装”。
3. 按向导完成初始化，下载 Ubuntu RootFS，并安装基础包、Node.js 与 OpenClaw。
4. 如有旧配置，可在安装完成后直接导入快照恢复。
5. 在首页启动 Gateway。
6. 点击首页地址，或在浏览器访问 `http://127.0.0.1:18789` 打开 Web 控制台。

## 系统要求

- Android 10+（API 29 及以上）
- 首次安装建议预留至少 500 MB 可用空间
- 首次初始化需要联网

## 文件校验（SHA256）

- `OpenClaw-v1.9.0-universal.apk`: `102A33C4A599CC019C2DFB3973D42D35261AC1E14434545A51F7EA3D1975FA20`
- `OpenClaw-v1.9.0-arm64-v8a.apk`: `4EE554E128D2379D000B1374080648A8FDCAD7818392EEF8BC3D6BC768D3B157`
- `OpenClaw-v1.9.0-armeabi-v7a.apk`: `50451930518859C93963E8B657BCD944B2A24DDA16649F4E5ADA58FEC21F0605`
- `OpenClaw-v1.9.0-x86_64.apk`: `5355CC954C17681ACF41AED521324455379D1B9F10838AB7BA9B9CABEBE41492`
- `OpenClaw-v1.9.0.aab`: `982B83B8A7DCA8E092B84A3BAA3CE9A74346C5C2892D12B19A8D948FBA5D9EE1`
