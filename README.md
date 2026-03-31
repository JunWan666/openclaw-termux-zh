<div align="center">
  <h1>OpenClaw 中文整合版（openclaw-termux-zh）</h1>
  <p>
    <a href="README.md">简体中文</a> | <a href="docs/README_en.md">English</a>
  </p>
  <img src="assets/ic_launcher.png" alt="OpenClaw" width="160" />
  <h3 align="center">面向中文用户维护与分发的 OpenClaw Android 独立整合版本</h3>
  <p align="center">内置 Ubuntu RootFS、Node.js、OpenClaw 安装与管理能力，重点优化中文文档、移动端配置体验与 Android 原生集成。</p>
  <p align="center">
    <img src="https://img.shields.io/badge/Version-v1.9.7-D32222?style=for-the-badge" alt="Version" />
    <img src="https://img.shields.io/badge/Android-10%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" />
    <img src="https://img.shields.io/badge/License-MIT-111827?style=for-the-badge" alt="License" />
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/Flutter-App_Shell-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" />
    <img src="https://img.shields.io/badge/Dart-UI_Logic-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart" />
    <img src="https://img.shields.io/badge/Kotlin-Android_Service-7F52FF?style=flat-square&logo=kotlin&logoColor=white" alt="Kotlin" />
    <img src="https://img.shields.io/badge/Ubuntu-RootFS-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu" />
    <img src="https://img.shields.io/badge/Node.js-Runtime-339933?style=flat-square&logo=nodedotjs&logoColor=white" alt="Node.js" />
    <img src="https://img.shields.io/badge/OpenClaw-Gateway-0F172A?style=flat-square" alt="OpenClaw" />
  </p>
</div>

> 本仓库为中文整合版，主要用于中文用户维护与分发。
>
> 整合来源：
> - 上游项目：[`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - 汉化分支作者：[`TIANLI0/openclaw-termux` 的 `feature/translation` 分支](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## 当前发布版本

- 版本：`v1.9.7`
- 发布说明：见 [release/v1.9.7/Release.zh.md](release/v1.9.7/Release.zh.md)
- 改动日志：见 [CHANGELOG.md](CHANGELOG.md)
- Releases 页面：<https://github.com/JunWan666/openclaw-termux-zh/releases>

## 下载指南

> 不确定手机架构时，优先下载 `universal.apk`。

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.7-universal.apk` | 不确定架构、想直接安装 | 44.04 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-universal.apk) |
| `OpenClaw-v1.9.7-arm64-v8a.apk` | 大多数现代 Android 手机 | 27.02 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-arm64-v8a.apk) |
| `OpenClaw-v1.9.7-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.66 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-armeabi-v7a.apk) |
| `OpenClaw-v1.9.7-x86_64.apk` | 模拟器或 x86_64 设备 | 27.23 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-x86_64.apk) |
| `OpenClaw-v1.9.7.aab` | 应用商店分发 | 50.85 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7.aab) |

## v1.9.7 亮点

- “安装所选版本”增加二次确认，并在已安装相同版本时直接提示，无需重复下载。
- 快照导出文件名会携带 App 版本和 OpenClaw 版本，导入前也会校验版本差异并给出继续提醒。
- 网关 token 改为优先从 `openclaw.json` / `.env` 读取，首页控制台地址与 Node 连接的鉴权来源更稳定。
- 兼容过滤部分上游噪声日志，并把本地兼容模式、Bonjour 重试、定价超时等信息改成更易读的提示。
- Ubuntu RootFS 默认时区改为 `Asia/Shanghai`，同时为 cpolar 额外补齐 `resolv.conf` 兜底，减少初始化失败。

## 快速开始

### 方式一：Android APK（推荐）

1. 从上方“下载指南”中选择适合自己设备的 APK。
2. 安装后打开应用。
3. 如需指定 OpenClaw 版本，可先在安装页上方选择版本，再点击“开始安装”。
4. 完成 Onboarding、模型提供商与 API Key 配置。
5. 启动 Gateway。
6. 点击首页地址，或在浏览器访问 `http://127.0.0.1:18789` 打开 Web 控制台。

### 方式二：源码构建

```bash
git clone https://github.com/JunWan666/openclaw-termux-zh.git
cd openclaw-termux-zh/flutter_app
flutter pub get
flutter build apk --release
```

如需直接生成发布目录中的 APK / AAB，可使用仓库自带脚本：

```bash
python scripts/build_release.py --version 1.9.7 --build-number 40
```

## 目录说明

- `flutter_app/`：Flutter Android 主应用
- `lib/`：Node / CLI 相关脚本
- `scripts/`：构建与依赖准备脚本
- `release/`：发布产物与版本说明
- `docs/README_en.md`：英文文档
- `CHANGELOG.md`：版本改动记录

## 交流反馈

如需交流使用经验、排查问题或反馈建议，欢迎加入 `OpenClaw-zh` 开源项目交流群。

<div align="center">
  <img src="docs/openclaw-termux-zh-weixin-04-07.png" alt="OpenClaw-zh 开源项目交流群 微信群二维码" width="320" />
  <p>微信扫码加入交流群</p>
</div>

## 免责声明

本仓库为社区维护的中文整合版本，不代表上游官方发布。若用于生产环境，请自行评估兼容性与风险。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
