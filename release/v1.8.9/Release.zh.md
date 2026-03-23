# OpenClaw Android 中文版 v1.8.9

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 新增 OpenClaw 版本选择：安装首页与首页网关卡片都可拉取已发布版本，默认选中最新版本，也可手动安装、重装、升级或降级指定版本。
- 版本选择会同步展示对应安装体积和 Node.js 要求；如内置 Node.js 版本不足，安装流程会先自动补齐再继续。
- 快照导入改为 Android 文件选择器；安装完成页新增“导入快照”按钮，恢复已有配置更直接。
- 快照导出支持先手动输入文件名，再保存到设备目录。
- 新增可选网关日志持久化：写入 `/root/openclaw.log`，单文件超过 5 MB 自动轮转，最多保留 3 份历史日志。
- 首页网关卡片排版细节优化，当前模型、版本和更新信息更紧凑，移动端查看更清晰。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.8.9-universal.apk` | 不确定架构时优先下载 | 43.52 MB | [点击下载](./OpenClaw-v1.8.9-universal.apk) |
| `OpenClaw-v1.8.9-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.84 MB | [点击下载](./OpenClaw-v1.8.9-arm64-v8a.apk) |
| `OpenClaw-v1.8.9-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.46 MB | [点击下载](./OpenClaw-v1.8.9-armeabi-v7a.apk) |
| `OpenClaw-v1.8.9-x86_64.apk` | 模拟器或 x86_64 设备 | 27.04 MB | [点击下载](./OpenClaw-v1.8.9-x86_64.apk) |
| `OpenClaw-v1.8.9.aab` | 应用商店分发 | 50.34 MB | [点击下载](./OpenClaw-v1.8.9.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.8.9`。
2. 如果上游某个最新 `openclaw` 版本临时异常，可在安装页或首页网关卡片中手动选择其他已发布版本后再安装。
3. 如果你已经有备份配置，可在安装完成页直接点击“导入快照”恢复，无需重新逐项配置 API Key。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，如需避开上游异常版本，可先选择目标 OpenClaw 版本，再点击“开始安装”。
3. 按向导完成初始化，下载 Ubuntu RootFS，并安装基础包、Node.js 与 OpenClaw。
4. 如有旧配置，可在安装完成后直接导入快照恢复。
5. 在首页启动 Gateway。
6. 点击首页地址，或在浏览器访问 `http://127.0.0.1:18789` 打开 Web 控制台。

## 系统要求

- Android 10+（API 29 及以上）
- 首次安装建议预留至少 500 MB 可用空间
- 首次初始化需要联网

## 文件校验（SHA256）

- `OpenClaw-v1.8.9-universal.apk`: `EA6B28F9061BDA2E7281B46D5E5E7932CD6D565BCA48E59AAC96EEC818FF306D`
- `OpenClaw-v1.8.9-arm64-v8a.apk`: `6797FFD12AE38B07CA50F17D43A763D82110C9AFF31E3E113B6446DF921FA12F`
- `OpenClaw-v1.8.9-armeabi-v7a.apk`: `FD0B4996FBCA026D0E387283BEFF2722632EEB0CA96F3C2A37B19E2F624E5C85`
- `OpenClaw-v1.8.9-x86_64.apk`: `BBB3F4079BFAA1992639F5AB27FDD98A888CB0EF5B9DBD4AD4E5D195DB03CBAF`
- `OpenClaw-v1.8.9.aab`: `DACBCE5B0E67EEF749FAF312B64B0759FF0046CDA6F13732E8404296F44D90D6`
