# basic-resource

这是 OpenClaw Android 中文整合版安装向导可选使用的基础运行时资源包，不是 App 正式版本发布。

建议 GitHub Release 设置：

- Tag：`basic-resource`
- Release title：`basic-resource`
- 不要勾选 `Set as the latest release`
- 不需要标记为正式 App 版本；它只是给安装向导和用户手动下载使用的资源附件

## 用途说明

从 v2.0.2 build 71 开始，APK 不再内置大体积 RootFS / Node.js 运行时资源，以降低安装包体积。首次初始化时，应用会在线下载所需资源；如果网络较慢，也可以使用本 Release 的附件作为外部资源。

如果在 App 里使用，进入安装页的“预构建资源配置”，可以直接点击“使用 GitHub 资源”，应用会自动填入下面 3 个附件链接：

```text
https://github.com/JunWan666/openclaw-termux-zh/releases/download/basic-resource/openclaw-rootfs-noble-arm64.tar.gz
https://github.com/JunWan666/openclaw-termux-zh/releases/download/basic-resource/ubuntu-base-24.04.3-base-arm64.tar.gz
https://github.com/JunWan666/openclaw-termux-zh/releases/download/basic-resource/node-v24.14.1-linux-arm64.tar.xz
```

也可以手动分别填入“预构建 RootFS”“Ubuntu base RootFS”“Node.js 运行时”三个输入框，或分别选择本地文件。若预构建 RootFS 解压或校验失败，应用会自动回退到标准 Ubuntu base rootfs 在线初始化流程。

## 附件说明

| 文件 | 用途 | 大小 |
| --- | --- | ---: |
| `openclaw-rootfs-noble-arm64.tar.gz` | arm64 预构建 Ubuntu RootFS，已包含 `ca-certificates git python3 make g++ curl wget` 等基础包，推荐给大多数现代 Android 手机使用 | 140.20 MB |
| `ubuntu-base-24.04.3-base-arm64.tar.gz` | Ubuntu 24.04.3 arm64 官方 base rootfs 备份资源，适合标准在线初始化流程兜底 | 28.48 MB |
| `node-v24.14.1-linux-arm64.tar.xz` | Node.js 24.14.1 arm64 运行时压缩包，供安装流程下载或本地缓存复用 | 28.67 MB |

## 直接下载链接

- [openclaw-rootfs-noble-arm64.tar.gz](https://github.com/JunWan666/openclaw-termux-zh/releases/download/basic-resource/openclaw-rootfs-noble-arm64.tar.gz)
- [ubuntu-base-24.04.3-base-arm64.tar.gz](https://github.com/JunWan666/openclaw-termux-zh/releases/download/basic-resource/ubuntu-base-24.04.3-base-arm64.tar.gz)
- [node-v24.14.1-linux-arm64.tar.xz](https://github.com/JunWan666/openclaw-termux-zh/releases/download/basic-resource/node-v24.14.1-linux-arm64.tar.xz)

## SHA256

- `openclaw-rootfs-noble-arm64.tar.gz`: `755EAA05383339FCD0C2DE528C907848F1D38A283C14D3EA0FDB63105874AD5E`
- `ubuntu-base-24.04.3-base-arm64.tar.gz`: `7B2DCED6DD56AD5E4A813FA25C8DE307B655FDABC6EA9213175A92C48DABB048`
- `node-v24.14.1-linux-arm64.tar.xz`: `71E427E28B78846F201D4D5ECC30CB13D1508CA099EF3871889A1256C7D6F67E`

## 使用提醒

1. 这三个附件只覆盖 arm64 设备。大多数现代 Android 手机都是 arm64；32 位 ARM 或 x86_64 设备不要使用这里的预构建 RootFS。
2. 如果只想让用户快速初始化，优先提供 `openclaw-rootfs-noble-arm64.tar.gz`；如果希望兜底链路也走 GitHub 资源，再同时提供 Ubuntu base 与 Node.js 两个链接。
3. 如果用户选择普通在线初始化，应用仍会按默认流程下载 Ubuntu base、Node.js 与 OpenClaw。
4. 资源包体积较大，建议在 Wi-Fi 环境下载，并确保手机有足够存储空间。
