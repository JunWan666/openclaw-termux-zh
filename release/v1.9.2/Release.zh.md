# OpenClaw Android 中文版 v1.9.2

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 首页左上角 `OpenClaw` 标题右侧新增轻量化的检查更新按钮，默认是低存在感的小图标，不会太打扰主界面。
- 当检测到新版本时，这个按钮会自动切换成更明显的更新样式，并显示小红点，方便你一眼看出“现在有更新可装”。
- 首页会在首次进入、应用回到前台，以及从设置等页面返回后静默刷新更新状态，减少必须手动进入设置页检查的步骤。
- 首页标题按钮和设置页“检查更新”现在共用同一套下载、安装和失败回退逻辑，体验更一致。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.2-universal.apk` | 不确定架构时优先下载 | 43.87 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.2/OpenClaw-v1.9.2-universal.apk) |
| `OpenClaw-v1.9.2-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.95 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.2/OpenClaw-v1.9.2-arm64-v8a.apk) |
| `OpenClaw-v1.9.2-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.58 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.2/OpenClaw-v1.9.2-armeabi-v7a.apk) |
| `OpenClaw-v1.9.2-x86_64.apk` | 模拟器或 x86_64 设备 | 27.15 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.2/OpenClaw-v1.9.2-x86_64.apk) |
| `OpenClaw-v1.9.2.aab` | 应用商店分发 | 50.69 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.2/OpenClaw-v1.9.2.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.9.2`。
2. 升级后可以直接在首页左上角通过新的小更新按钮查看版本状态，不必再只依赖设置页入口。
3. 当按钮出现红点时，表示当前已经检测到有可安装的新版本，点一下即可进入更新流程。
4. 如果应用内下载或安装失败，仍会自动回退到浏览器打开对应的 Release 下载页。

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

- `OpenClaw-v1.9.2-universal.apk`: `DA5F3315F6E1764F7978AF05E7D1B52BDA7B6ADCAE023762F194FC2A8CB8C49A`
- `OpenClaw-v1.9.2-arm64-v8a.apk`: `9E179EF9BE4B54665569AC7349E67BF3C86A22378F5C175C3459F4793B8D05FD`
- `OpenClaw-v1.9.2-armeabi-v7a.apk`: `CFD3F18EE70F8954B214CE4DF0291CFB58FB573FDF2AB288F0C39292705B781F`
- `OpenClaw-v1.9.2-x86_64.apk`: `A50944E595685FFAB31A62D4BDB4051182316EF5333D48D107E062904446D30B`
- `OpenClaw-v1.9.2.aab`: `97F39F7B887D5E0F35C97210EB1A19239F96A9BC2A1CCF580E786F93450DD43C`
