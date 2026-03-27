# OpenClaw Android 中文版 v1.9.4

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 修复部分用户在安装完成或网关重启后，首页控制台地址没有自动带上 `#token=` 的问题；现在会优先从日志提取 token URL。
- 当日志中没有及时出现完整 token URL 时，应用会在网关健康后主动向控制台发起探测，请求补全首页地址中的 `#token=`。
- token URL 解析兼容性增强，不再只依赖 `localhost` / `127.0.0.1` 的固定格式，同时支持 query / fragment token 和部分响应体里的 token 信息。
- 启动网关时改为先订阅日志再拉起网关进程，减少因监听过晚导致首条 token 地址漏抓的问题。
- 同步统一 Node 侧读取网关 token 的解析逻辑，并修正 CLI 脚本中的版本号显示，避免版本元数据不一致。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.4-universal.apk` | 不确定架构时优先下载 | 43.89 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.4/OpenClaw-v1.9.4-universal.apk) |
| `OpenClaw-v1.9.4-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.96 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.4/OpenClaw-v1.9.4-arm64-v8a.apk) |
| `OpenClaw-v1.9.4-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.59 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.4/OpenClaw-v1.9.4-armeabi-v7a.apk) |
| `OpenClaw-v1.9.4-x86_64.apk` | 模拟器或 x86_64 设备 | 27.16 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.4/OpenClaw-v1.9.4-x86_64.apk) |
| `OpenClaw-v1.9.4.aab` | 应用商店分发 | 50.71 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.4/OpenClaw-v1.9.4.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.9.4`。
2. 如果首页控制台地址之前偶发没有带 `#token=`，升级到这个版本后，应用会优先从日志抓取，抓不到时再主动向网关补探测，不需要手动重新找 token。
3. 如果你是通过 app 内更新覆盖安装，原有网关配置会保留；如遇到首页 URL 仍未刷新，可先重启一次网关让应用重新抓取控制台地址。
4. 如果控制台地址仍异常，仍可通过设置中的日志查看最近的网关输出，辅助判断是否为上游输出格式变化。

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

- `OpenClaw-v1.9.4-universal.apk`: `151A513A4C25133860DE7EDC4C1FAE4BB4C0DF357F25820DFFB64F2C311D5D37`
- `OpenClaw-v1.9.4-arm64-v8a.apk`: `ADD631075F64FAA82B288183DB536A363096DA6F31B1B7072A0617250FBD6F7F`
- `OpenClaw-v1.9.4-armeabi-v7a.apk`: `B73C79D7005530F36FA5D8B3929F9FD5E1FD6614638F10F0BF4DC8575680A7D0`
- `OpenClaw-v1.9.4-x86_64.apk`: `6C28871AAAE45A431B0D9FAF93D4C7631E8FEB22AD5AAC4C4D61988CB936F602`
- `OpenClaw-v1.9.4.aab`: `DDEF03519FDA7DB100B1720F1C5BE22CDB2DED1CCAABFBF4F501AA17525CA4BA`
