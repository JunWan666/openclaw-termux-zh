# OpenClaw Android 中文版 v1.9.3

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 修复应用内更新在下载完成后直接跳到浏览器下载页的问题；现在会优先尝试调起 Android 系统安装器。
- 当设备尚未允许 OpenClaw 安装未知应用时，更新流程会先打开系统授权页；授权返回后会继续尝试安装，不需要自己重新去找安装包。
- 只有真正无法在应用内完成安装时，才会回退到浏览器下载页，并显示更明确的错误提示。
- 同步补充了简中、繁中、英文、日文的安装权限提示文案，让不同语言界面的更新反馈保持一致。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.3-universal.apk` | 不确定架构时优先下载 | 43.87 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.3/OpenClaw-v1.9.3-universal.apk) |
| `OpenClaw-v1.9.3-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.95 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.3/OpenClaw-v1.9.3-arm64-v8a.apk) |
| `OpenClaw-v1.9.3-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.58 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.3/OpenClaw-v1.9.3-armeabi-v7a.apk) |
| `OpenClaw-v1.9.3-x86_64.apk` | 模拟器或 x86_64 设备 | 27.15 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.3/OpenClaw-v1.9.3-x86_64.apk) |
| `OpenClaw-v1.9.3.aab` | 应用商店分发 | 50.69 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.3/OpenClaw-v1.9.3.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.9.3`。
2. 应用内更新下载完成后，会优先调起 Android 系统安装器；如果系统要求允许“安装未知应用”，请先授权再返回应用继续安装。
3. 如果你拒绝了“安装未知应用”权限，应用会明确提示当前无法继续安装，而不会误导成普通下载失败。
4. 如果应用内安装链路仍然失败，才会自动回退到浏览器打开对应的 Release 下载页。

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

- `OpenClaw-v1.9.3-universal.apk`: `4C98C5312315B828A2BB8C329FC9429B66AFD57C833B9ACC1FD0256F1FEE2ADB`
- `OpenClaw-v1.9.3-arm64-v8a.apk`: `9DF4F6C90342CDD95F4AEA1E71983339CD847231575D81773A9EF604800DDB0C`
- `OpenClaw-v1.9.3-armeabi-v7a.apk`: `56FC1AC076F3884128F39AEF37FD2767C28B1CD7528EAFE8C433794FAF07E88D`
- `OpenClaw-v1.9.3-x86_64.apk`: `B9B5B95ED7E3F7645557883E2846D64DDF4B9937CF405572E0355B82F69B148E`
- `OpenClaw-v1.9.3.aab`: `CEE45E019E13CB4A05F0D00EF8B8BC168789109FA8F7A797146BC1FE22EFFE07`
