# OpenClaw Android 中文版 v1.9.1

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 新增 QQ 机器人接入页，进入页面后会自动检测并安装 `@tencent-connect/openclaw-qqbot@latest` 插件，可快捷打开腾讯 QQ Bot 接入页面；保存时会执行 `openclaw channels add --channel qqbot --token "<AppID>:<AppSecret>"` 完成绑定。
- 新增微信接入入口与独立绑定终端，可检测微信插件状态，并一键执行 `npx -y @tencent-weixin/openclaw-weixin-cli install`；终端中的二维码或登录链接可直接扫码、截图或复制后继续绑定。
- 应用内检查更新现在会从 GitHub Release 读取全部安装包，自动识别当前机型并优先下载对应 APK；下载完成后会直接调起 Android 系统安装器。
- 如果应用内下载或安装失败，会自动回退到浏览器打开对应 Release 下载页，避免更新链路卡死。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.1-universal.apk` | 不确定架构时优先下载 | 43.83 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.1/OpenClaw-v1.9.1-universal.apk) |
| `OpenClaw-v1.9.1-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.94 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.1/OpenClaw-v1.9.1-arm64-v8a.apk) |
| `OpenClaw-v1.9.1-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.57 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.1/OpenClaw-v1.9.1-armeabi-v7a.apk) |
| `OpenClaw-v1.9.1-x86_64.apk` | 模拟器或 x86_64 设备 | 27.14 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.1/OpenClaw-v1.9.1-x86_64.apk) |
| `OpenClaw-v1.9.1.aab` | 应用商店分发 | 50.65 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.1/OpenClaw-v1.9.1.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.9.1`。
2. 如果你准备接入 QQ 机器人，建议先在 QQ 接入页完成 AppID / AppSecret 配置并保存，保存成功后按提示重启 Gateway。
3. 如果你准备接入个人微信，请在微信接入页打开安装终端，按终端里显示的二维码或链接完成绑定。
4. 后续从应用内执行检查更新时，会自动选择更适合当前设备的 APK，并在下载完成后直接调起系统安装器。

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

- `OpenClaw-v1.9.1-universal.apk`: `5C141C9738292BE7318D91293DA616C857F395D9A80780F90221AAF16338E148`
- `OpenClaw-v1.9.1-arm64-v8a.apk`: `15CDC54AE84F690A919C1CE8B4B840CA295343F61C9E214E4715E40C90B1024D`
- `OpenClaw-v1.9.1-armeabi-v7a.apk`: `0349C74C54453048CA57C81C09D564CF60B53CD5A609026EADFCED8B61E8179D`
- `OpenClaw-v1.9.1-x86_64.apk`: `387FED93162E30C5FF78B59D829C023EC82CCCC508237ADA02637086B88DB650`
- `OpenClaw-v1.9.1.aab`: `842553DCB84A4904142815540EC6B88382EE7D46A4E15E844FC2603178F39290`
