# OpenClaw Android 中文版 v1.9.6

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 新增 `cpolar` 可选组件，支持安装、卸载、启动、停止、状态显示、Web 面板入口，以及安装过程中的实时日志滚动输出。
- 修复 QQ / 微信接入在部分设备上的 PRoot 原生库缺失问题：应用会先准备 `libproot.so`、loader 与 DNS 配置，必要时还能从 APK 中回退提取运行时依赖，提升插件初始化成功率。
- 首页控制台地址解析更稳，自动清理误拼接到 token 后面的 `copy`、`copied`、`GatewayWS` 等噪声后缀。
- 返回首页时会主动重新同步网关状态，尽量避免“后台仍在运行但首页显示已停止”的错位情况。
- 切换 OpenClaw 版本时新增百分比进度提示，长时间安装过程反馈更直观。
- 修改模型提供商、消息平台等关键配置后，如果网关正在运行，应用会自动重启网关应用配置。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.6-universal.apk` | 不确定架构时优先下载 | 44.01 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-universal.apk) |
| `OpenClaw-v1.9.6-arm64-v8a.apk` | 大多数现代 Android 手机 | 27.01 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-arm64-v8a.apk) |
| `OpenClaw-v1.9.6-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.64 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-armeabi-v7a.apk) |
| `OpenClaw-v1.9.6-x86_64.apk` | 模拟器或 x86_64 设备 | 27.22 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-x86_64.apk) |
| `OpenClaw-v1.9.6.aab` | 应用商店分发 | 50.82 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6.aab) |

## 升级提示

1. 本次正式版使用 Android 构建号 `39`。如果你之前安装过 `1.9.6.2` 测试包，可以直接覆盖安装正式版。
2. 首次安装 cpolar 时，建议直接在应用内查看滚动日志，等待安装流程结束后再点击“启动”或打开 Web 面板。
3. 如果你在本版本中重新配置了模型提供商、消息平台或自定义预设，应用会在网关运行中自动重启以应用新配置。
4. 若首页控制台地址曾出现 token 后缀被额外拼接的问题，本版本会自动清理并重新规范化该链接。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，可先选择目标 OpenClaw 版本，再点击“开始安装”。
3. 按向导完成初始化，下载 Ubuntu RootFS，并安装基础包、Node.js 与 OpenClaw。
4. 完成 API Key、模型提供商与消息平台配置。
5. 启动 Gateway，并点击首页地址打开 Web 控制台。

## 文件校验（SHA256）

- `OpenClaw-v1.9.6-universal.apk`: `F8667C2F91A655D7942C31C293DAFD70D17DC691F40B4C03D16C567A00A12AE5`
- `OpenClaw-v1.9.6-arm64-v8a.apk`: `B30F553924892E300F624A3FBB686C5042C72B9CD4E6817129F6C68E3035F1A4`
- `OpenClaw-v1.9.6-armeabi-v7a.apk`: `8CDDA6304A11303454FB7E82F2E6807CE45F0141F724A9B37E4D5228AD895260`
- `OpenClaw-v1.9.6-x86_64.apk`: `6872D8671D17531522779AF65743B237F57D493396DA6DAD5CAEEF018E9FB34D`
- `OpenClaw-v1.9.6.aab`: `5E54E758FF40E6AC4AE4B3573066220E1954C337A983F1A74EE54A317DABC8AA`
