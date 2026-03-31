# OpenClaw Android 中文版 v1.9.7

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 首页“安装所选版本”增加二次确认；若当前已安装版本与所选版本相同，会直接提示并阻止重复下载安装。
- 快照导出文件名现在会自动携带 App 版本与 OpenClaw 版本；导入快照时会先校验版本差异，必要时弹窗提醒后再继续恢复。
- 新增 `GatewayAuthConfigService`，优先从 `openclaw.json` / `.env` 读取网关 token，首页控制台地址和 Node 连接的鉴权来源更稳定。
- 兼容过滤 `xai-auth bootstrap config fallback`、`boot-md skipped` 等噪声日志，并把本地兼容模式、Bonjour 重试、模型定价超时等提示改写成更易读的说明。
- Ubuntu RootFS 默认时区切换为 `Asia/Shanghai`，同时为 cpolar 额外补齐 `config/resolv.conf` 与 RootFS 内 `etc/resolv.conf` 兜底，减少启动失败。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.7-universal.apk` | 不确定架构时优先下载 | 44.04 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-universal.apk) |
| `OpenClaw-v1.9.7-arm64-v8a.apk` | 大多数现代 Android 手机 | 27.02 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-arm64-v8a.apk) |
| `OpenClaw-v1.9.7-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.66 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-armeabi-v7a.apk) |
| `OpenClaw-v1.9.7-x86_64.apk` | 模拟器或 x86_64 设备 | 27.23 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-x86_64.apk) |
| `OpenClaw-v1.9.7.aab` | 应用商店分发 | 50.85 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7.aab) |

## 升级提示

1. 本次正式版使用 Android 构建号 `40`，可覆盖安装之前的 `1.9.7` 测试包。
2. 如果你经常通过快照迁移配置，建议优先选择与当前 OpenClaw 版本相近的快照；版本不一致时，应用会先提醒再决定是否导入。
3. 首页控制台地址与 Node 鉴权现在优先读取配置文件中的 token；如你曾手动改动过 `gateway.auth.token` 或 `.env`，建议确认其值仍然有效。
4. cpolar 如曾出现 `resolv.conf` 缺失导致的启动异常，本版本会在初始化前自动补齐 DNS 文件。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，可先选择目标 OpenClaw 版本，再点击“开始安装”。
3. 按向导完成初始化，下载 Ubuntu RootFS，并安装基础包、Node.js 与 OpenClaw。
4. 完成 API Key、模型提供商与消息平台配置。
5. 启动 Gateway，并点击首页地址打开 Web 控制台。

## 文件校验（SHA256）

- `OpenClaw-v1.9.7-universal.apk`: `D8A73AB9177E28AB3C0E59E643DD8F2D8EC9829F84447E54179E52054EBD20F4`
- `OpenClaw-v1.9.7-arm64-v8a.apk`: `4C61E246BA16C5B828005433E53C6A269DEE8B9C73875BF5D9E051590FAA84B6`
- `OpenClaw-v1.9.7-armeabi-v7a.apk`: `B75EDDADDA8DB3289C08C72E20C1A38999351C77C8A7DB8D8B728EE282B49978`
- `OpenClaw-v1.9.7-x86_64.apk`: `1BBE17C968D108FD007F111AB04481F190DEA89C2592D385BE612524D83DB13B`
- `OpenClaw-v1.9.7.aab`: `4FEED8DD845BD0C66280CD4D114CED1B4BC05873624DF82FDF2863A422617C45`
