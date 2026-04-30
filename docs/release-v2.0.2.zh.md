# OpenClaw Android 中文版 v2.0.2

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 新增 arm64 预构建 Ubuntu rootfs：已内置 `ca-certificates git python3 make g++ curl wget`，首次 setup 会优先解压它，跳过现场 `apt-get update/install`，减少国产 ROM 在“更新软件列表”阶段拦截 PRoot 的概率。
- 预构建 rootfs 有兜底：如果内置包缺失、解压失败，或基础包校验不通过，会自动回退到标准 Ubuntu base rootfs + 在线 apt 流程。
- 修复 32 位 ARM / `armeabi-v7a` 设备初始化时下载 Node.js 24 `linux-armv7l` 包返回 404 的问题；armv7 现在单独使用官方仍提供的 Node.js 22.22.2，arm64 和 x86_64 继续使用 Node.js 24.14.1。
- 修复部分国内网络下初始化失败并提示 `Temporary failure resolving 'ports.ubuntu.com'` 的问题；DNS 兜底改为 `223.5.5.5`、`119.29.29.29`、`8.8.8.8`，Ubuntu 镜像探测失败时优先留在国内镜像候选。
- 初始化前会补齐 apt/dpkg 运行目录，例如 `/var/cache/apt/archives/partial` 和 `/var/lib/apt/lists/partial`，减少 apt `exit code 100`。
- PRoot 命令失败摘要改为优先显示真正的 `E:`、`Err:`、`dpkg:` 和 DNS 解析错误，不再只显示一串依赖包名。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v2.0.2-universal.apk` | 不确定架构时优先下载 | 240.91 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-universal.apk) |
| `OpenClaw-v2.0.2-arm64-v8a.apk` | 大多数现代 Android 手机 | 222.64 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-arm64-v8a.apk) |
| `OpenClaw-v2.0.2-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 222.38 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-armeabi-v7a.apk) |
| `OpenClaw-v2.0.2-x86_64.apk` | 模拟器或 x86_64 设备 | 222.85 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-x86_64.apk) |

## 升级提示

1. 本次版本使用 Android 构建号 `69`，可覆盖安装 v2.0.1。
2. 遇到过初始化 DNS / apt 失败的设备，建议升级后重新运行 setup；如果 rootfs 已经处于半初始化状态，清理环境后重跑会更干净。
3. 由于内置 arm64 预构建 rootfs，本版 APK 体积明显增加。
4. 32 位 ARM 设备请使用 `armeabi-v7a` 或 `universal` 包。

## 文件校验（SHA256）

- `OpenClaw-v2.0.2-universal.apk`: `E2C1754392FF09F564263857B1453A41D511E4A9F51B1DF152A0707C8061DB34`
- `OpenClaw-v2.0.2-arm64-v8a.apk`: `4BB549E18EDAB82BFB5B17D344386A8A88C9DC9F1C57C6FA9DA3F1DA3A2B1E2D`
- `OpenClaw-v2.0.2-armeabi-v7a.apk`: `6F8BFABE59DAA02079C20714338DAB050E99937BFF4776163CEAB5FA3B12DDF0`
- `OpenClaw-v2.0.2-x86_64.apk`: `F7D79193AE76B48170AC95CCBBAC0E521784DBC04EA468C56DE0BF34295AFDE5`
