# OpenClaw Android 中文版 v1.9.5

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 设置页导出快照时，改为直接调用 Android 系统保存面板，可自行选择保存位置与文件名，不再把备份固定塞到应用目录里。
- Android 原生桥接新增快照写入能力，导出完成后会返回真实保存的文件名，便于确认备份是否落到了你想要的位置。
- AI 提供商列表新增独立的 `智谱 AI` 入口，内置官方基础地址 `https://open.bigmodel.cn/api/paas/v4` 与常用 `GLM` 模型预设。
- 自定义提供商新增 `智谱 AI Compatible` 兼容模式；当基础地址是 `bigmodel.cn` 时，会优先按智谱接口规则测试和保存，不再错误补成 `/v1`。
- 简中、繁中、英文、日文的智谱与快照相关提示文案同步更新，自定义提供商连接测试也补充了对应自动识别与地址归一化测试。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.5-universal.apk` | 不确定架构时优先下载 | 43.89 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.5/OpenClaw-v1.9.5-universal.apk) |
| `OpenClaw-v1.9.5-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.96 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.5/OpenClaw-v1.9.5-arm64-v8a.apk) |
| `OpenClaw-v1.9.5-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.59 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.5/OpenClaw-v1.9.5-armeabi-v7a.apk) |
| `OpenClaw-v1.9.5-x86_64.apk` | 模拟器或 x86_64 设备 | 27.16 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.5/OpenClaw-v1.9.5-x86_64.apk) |
| `OpenClaw-v1.9.5.aab` | 应用商店分发 | 50.71 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.5/OpenClaw-v1.9.5.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.9.5`。
2. 导出快照时会弹出 Android 系统文件保存面板，请直接选择你想保存的目录；不再需要手动去应用私有目录里找备份。
3. 如果你要接入智谱，请优先使用内置的 `智谱 AI` 提供商，或在自定义提供商里选择 `智谱 AI Compatible`，基础地址填写到 `https://open.bigmodel.cn/api/paas/v4` 即可，不要额外补 `/v1`。
4. 自定义提供商保存前仍可先做 API 测试；如果接口暂时不可用，应用会先提示失败原因，再由你决定是否继续保存。

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

- `OpenClaw-v1.9.5-universal.apk`: `82F439D01E06F8B7363304E843F74DD85B7F1710B8D14222D2E0449FA9B86C40`
- `OpenClaw-v1.9.5-arm64-v8a.apk`: `353BE9611AFA5C850591857C731D0EC23823F18CF4BAA9EAF3CE170AA2603F2A`
- `OpenClaw-v1.9.5-armeabi-v7a.apk`: `B4B6F76998320CB35B2FBBA2E5E86180C19E3B89AF341CAF55622CDE957639B1`
- `OpenClaw-v1.9.5-x86_64.apk`: `163A301197D6718DFCDF9872A96E86C246019BCF347F1DD9258861A86E426D47`
- `OpenClaw-v1.9.5.aab`: `77A974CBDA82184D476FC52BD70C96A83CD99B70FD62D1519F41BA3861A70907`
