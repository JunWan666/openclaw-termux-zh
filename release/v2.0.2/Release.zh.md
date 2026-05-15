# OpenClaw Android 中文版 v2.0.2

独立 Android 应用，无需单独安装 Termux。本次 v2.0.2 合并了初始化稳定性修复、上一轮终端性能优化与当前未发布改动，Android 构建号为 `77`。

## 本次更新

- APK 不再内置 `assets/bootstrap/` 下的大体积 RootFS / Node.js 资源，通用包约 45.96 MB，分 ABI 包约 27 MB。
- 预构建资源配置从安装页挪到独立页面，不再挤占主安装界面；可一键使用 GitHub `basic-resource` 资源，也可分别填写或选择预构建 RootFS、Ubuntu base RootFS、Node.js 三个资源。
- 首次安装向导改为小图标标题、步骤时间线和更紧凑的设置区；预构建资源页与示例配置弹窗补齐简体、繁体、英文、日文本地化。
- 保留预构建 RootFS 校验与失败兜底：外部或本地包缺失、解压失败、基础包校验不通过时，会回退到标准 Ubuntu base rootfs + 在线 apt 流程。
- 修复 32 位 ARM / `armeabi-v7a` 设备初始化时下载 Node.js 24 `linux-armv7l` 包返回 404 的问题；armv7 使用 Node.js 22.22.2，arm64 与 x86_64 使用 Node.js 24.14.1。
- 优化国内网络 DNS 与 Ubuntu 镜像兜底，补齐 apt/dpkg 运行目录，并让 PRoot 失败摘要优先显示真正的 `E:`、`Err:`、`dpkg:` 和 DNS 解析错误。
- 终端输出改为 16ms 批量刷新，终端历史收敛到 3000 行，普通交互终端默认使用更轻的 PRoot fast 模式。
- DNS 初始化统一收口到 `ProotDnsService.ensureReady()`，减少进入终端前重复写 `resolv.conf`。
- 内置示例配置默认使用 OpenAI 兼容测试提供商，方便新用户快速验证安装后的链路。
- 本地模型页顶部补充强提醒：当前方案是 PRoot + llama.cpp + GGUF CPU，不是 Google AI Edge 原生 GPU。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v2.0.2-universal.apk` | 不确定架构时优先下载 | 45.96 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-universal.apk) |
| `OpenClaw-v2.0.2-arm64-v8a.apk` | 大多数现代 Android 手机 | 27.66 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-arm64-v8a.apk) |
| `OpenClaw-v2.0.2-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 27.40 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-armeabi-v7a.apk) |
| `OpenClaw-v2.0.2-x86_64.apk` | 模拟器或 x86_64 设备 | 27.87 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-x86_64.apk) |
| `OpenClaw-v2.0.2.aab` | 应用商店分发 | 52.74 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2.aab) |

## 升级提示

1. 本次版本使用 Android 构建号 `77`，可覆盖安装 v2.0.1 及此前测试包。
2. APK 已移除内置大体积运行时资源，首次初始化需要稳定网络与足够前台运行时间；如需使用外部资源，可进入“预构建资源配置”页选择 GitHub 默认资源、自托管链接或本地压缩包。
3. 遇到初始化 DNS / apt 失败的设备，建议升级后重新运行 setup；如果 rootfs 已经处于半初始化状态，清理环境后重跑会更干净。
4. 32 位 ARM 设备请使用 `armeabi-v7a` 或 `universal` 包。
5. 本地模型功能当前不是手机 GPU 原生推理路径，资源占用和速度请按 CPU 方案预期评估。

## 文件校验（SHA256）

- `OpenClaw-v2.0.2-universal.apk`: `21793E2D0C09DE288B89D86B368164FD3989D3BA7939E98C5AE7D7CD0FB60849`
- `OpenClaw-v2.0.2-arm64-v8a.apk`: `9539509461B1DCF9A6473BF632C5C07942E04496722BD67C1A479E546B397F16`
- `OpenClaw-v2.0.2-armeabi-v7a.apk`: `52826D97E3ED08A487B3A912D2866E56E29B08EE5B40AD3FE9A1DBFE63143679`
- `OpenClaw-v2.0.2-x86_64.apk`: `016E3C5669C8B4AFF73F1F36893DCD49F498DE97EF16731E1725AD558CA9F891`
- `OpenClaw-v2.0.2.aab`: `8EAA4CB7BAA81473F4167F5D5FC01F60885C069F2C1D7F6FF123CF924675FD31`
