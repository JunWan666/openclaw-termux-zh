# OpenClaw Android 中文版 v1.9.8

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 初始化现在会优先复用 APK 内置或本地缓存的 Ubuntu RootFS 与 Node.js 24 离线包，只有本地包缺失或损坏时才回退在线下载。
- 安装向导与首页“安装所选版本”改成更真实的阶段进度，支持展示下载体积、实时速度、预计剩余时间与滚动小字日志。
- Ubuntu 基础包安装前会自动探测更快的镜像源；OpenClaw 安装链路细化为下载、依赖安装、bin wrapper 创建与版本校验等阶段。
- 首页网关状态、控制台 URL 刷新和配置保存后的热更新更稳定；设置页“维护”区域移动到“系统信息”上方。
- 正式发布元数据已同步到 `v1.9.8`，Android 正式包名恢复为 `com.junwan666.openclawzh`。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.8-universal.apk` | 不确定架构时优先下载 | 100.27 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-universal.apk) |
| `OpenClaw-v1.9.8-arm64-v8a.apk` | 大多数现代 Android 手机 | 83.21 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-arm64-v8a.apk) |
| `OpenClaw-v1.9.8-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 82.84 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-armeabi-v7a.apk) |
| `OpenClaw-v1.9.8-x86_64.apk` | 模拟器或 x86_64 设备 | 83.41 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-x86_64.apk) |
| `OpenClaw-v1.9.8.aab` | 应用商店分发 | 107.08 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8.aab) |

## 升级提示

1. 本次正式版使用 Android 构建号 `43`，可以覆盖安装此前的正式包。
2. 如果你当前安装的是测试包 `com.junwan666.openclawzh.test198`，由于包名已恢复为正式包 `com.junwan666.openclawzh`，不能直接覆盖安装；建议先在旧包里导出快照，再安装正式包后导入。
3. 如果你之前已经把 Ubuntu RootFS、Node.js 或 OpenClaw 安装完成，新的初始化流程会优先复用本地缓存与已完成步骤，网络中断时也不容易回到最前面重新开始。
4. 安装与版本切换过程中看到 ETA 归零后，如果界面还在运行，通常是在执行解压、`apt-get install`、`npm install`、bin wrapper 创建或版本校验；这些阶段现在会在进度详情里持续显示实时日志。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，可先选择目标 OpenClaw 版本，再点击“开始安装”。
3. 按向导完成 Ubuntu RootFS、基础包、Node.js 24 与 OpenClaw 的初始化。
4. 配置 API Key、模型提供商与消息通道。
5. 启动 Gateway，并点击首页地址打开 Web 控制台。

## 文件校验（SHA256）

- `OpenClaw-v1.9.8-universal.apk`: `29E55B871BE9EDFC9B186DCCB3BD1DFC212D39FBC0438F6EFA3E19D384666E02`
- `OpenClaw-v1.9.8-arm64-v8a.apk`: `2F27F6C22F38A9CE90A41227DC8995300B5A38E2B3CA54D6403BDC71F28A9A50`
- `OpenClaw-v1.9.8-armeabi-v7a.apk`: `C18B6547A9E2E81B068F692D09E6FB1C632C1A4DC97CD1D47BB4D69AA835585E`
- `OpenClaw-v1.9.8-x86_64.apk`: `47DB169FEE6AEBE044B0C801760F169FACD5DDCBBE72E498090E55824C92D864`
- `OpenClaw-v1.9.8.aab`: `B21815C4562100A35B28079440F57A06341FEE0C617D871D3AB2800C52FC3533`
