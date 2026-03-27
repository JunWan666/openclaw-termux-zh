<div align="center">
  <h1>OpenClaw 中文整合版（openclaw-termux-zh）</h1>
  <p>
    <a href="README.md">简体中文</a> | <a href="docs/README_en.md">English</a>
  </p>
  <img src="assets/ic_launcher.png" alt="OpenClaw" width="160" />
  <h3 align="center">面向中文用户维护与分发的 OpenClaw Android 独立整合版本</h3>
  <p align="center">内置 Ubuntu RootFS、Node.js、OpenClaw 安装与管理能力，重点优化中文文档、配置体验和移动端使用流程。</p>
  <p align="center">
    <img src="https://img.shields.io/badge/Version-v1.9.3-D32222?style=for-the-badge" alt="Version" />
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

> 本仓库为汉化整合版，主要用于中文用户维护与分发。
>
> 整合来源：
> - 上游项目：[`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - 汉化分支作者：[`TIANLI0/openclaw-termux` 的 `feature/translation` 分支](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)
>
> 本仓库在上游基础上整合了 i18n（简中 / 繁中 / 日文）相关改动，并以中文文档为主。

## 技术栈

<table>
  <tr>
    <td align="center" width="25%">
      <strong>Flutter + Dart</strong><br />
      <sub>Android UI、i18n、多页面交互</sub>
    </td>
    <td align="center" width="25%">
      <strong>Kotlin</strong><br />
      <sub>前台服务、PRoot 启动、系统桥接</sub>
    </td>
    <td align="center" width="25%">
      <strong>Ubuntu RootFS</strong><br />
      <sub>免 root 环境下的 Linux 用户态</sub>
    </td>
    <td align="center" width="25%">
      <strong>Node.js + OpenClaw</strong><br />
      <sub>AI Gateway、CLI 与更新链路</sub>
    </td>
  </tr>
</table>

---

## 当前发布版本

- 版本：`v1.9.3`
- 发布说明：见 [release/v1.9.3/Release.zh.md](release/v1.9.3/Release.zh.md)
- 改动日志：见 [CHANGELOG.md](CHANGELOG.md)
- Releases 页面：<https://github.com/JunWan666/openclaw-termux-zh/releases>

## 下载引导

> 不确定手机架构时，优先下载 `universal.apk`。

| 文件 | 适用设备 | 大小 | 最新下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.3-universal.apk` | 不确定架构、想直接安装 | 43.87 MB | [直接下载](https://github.com/JunWan666/openclaw-termux-zh/releases/latest/download/OpenClaw-v1.9.3-universal.apk) |
| `OpenClaw-v1.9.3-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.95 MB | [直接下载](https://github.com/JunWan666/openclaw-termux-zh/releases/latest/download/OpenClaw-v1.9.3-arm64-v8a.apk) |
| `OpenClaw-v1.9.3-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.58 MB | [直接下载](https://github.com/JunWan666/openclaw-termux-zh/releases/latest/download/OpenClaw-v1.9.3-armeabi-v7a.apk) |
| `OpenClaw-v1.9.3-x86_64.apk` | 模拟器或 x86_64 设备 | 27.15 MB | [直接下载](https://github.com/JunWan666/openclaw-termux-zh/releases/latest/download/OpenClaw-v1.9.3-x86_64.apk) |
| `OpenClaw-v1.9.3.aab` | 应用商店分发 | 50.69 MB | [直接下载](https://github.com/JunWan666/openclaw-termux-zh/releases/latest/download/OpenClaw-v1.9.3.aab) |

---

## 项目简介

OpenClaw 是一个在 Android 上运行的 AI Gateway 方案。该项目通过 Flutter + proot Ubuntu 环境，在免 root 设备上提供：

- 一键安装 Ubuntu RootFS + Node.js + OpenClaw
- 应用内终端、日志、Web 控制台与配置入口
- 网关管理、健康检查、版本选择与更新
- 可选工具包（如 Go、Homebrew、OpenSSH）
- 节点能力接入（相机、位置、传感器等）

## v1.9.3 亮点

- 修复应用内更新在下载完成后直接跳到浏览器下载页的问题；现在会优先尝试拉起 Android 系统安装器。
- 当设备尚未允许 OpenClaw 安装未知应用时，更新流程会先打开系统授权页；授权返回后会继续尝试安装，不用自己再去找安装包。
- 只有真正无法在应用内完成安装时，才会回退到浏览器下载页，并补充更明确的提示，方便区分“需要授权”和“安装异常”两类情况。

---

## 主要特性（中文整合版）

- 中文优先文档与维护流程
- i18n 文案与页面整合（含简中 / 繁中 / 日文）
- 保留上游核心功能与结构，便于后续同步
- 版本变更统一记录到 Release 文档与 Changelog

---

## 快速开始

### 方式一：Android APK（推荐）

1. 从上方“下载引导”表格选择对应 APK。
2. 安装后打开应用。
3. 如需指定 OpenClaw 版本，可先在安装页上方选择版本，再点击 **Begin Setup**。
4. 在应用内完成 Onboarding 与 API Key / 提供商配置。
5. 启动 Gateway。

### 方式二：源码构建

```bash
git clone https://github.com/JunWan666/openclaw-termux-zh.git
cd openclaw-termux-zh/flutter_app
flutter pub get
flutter build apk --release
```

说明：如果你需要可运行的 proot 相关 `.so`，请按仓库脚本准备 `jniLibs` 后再打包。

推荐：也可直接使用仓库内的 Python 发布脚本，它会交互输入版本号 / 构建号，并自动将 APK / AAB 整理到 `release/v版本/` 目录：

```bash
python scripts/build_release.py
```

---

## 目录说明

- `flutter_app/`：Flutter Android 主应用
- `lib/`：Node / CLI 相关脚本
- `scripts/`：构建与依赖准备脚本
- `release/`：发布产物与对应版本说明
- `docs/README_en.md`：英文文档
- `CHANGELOG.md`：版本与改动记录

---

## 与上游同步建议

如果后续要继续跟进上游更新，建议流程：

1. 同步上游 `main`
2. 在独立分支处理冲突
3. 回归测试安装、RootFS 解压、网关启动与版本更新
4. 更新本仓库 `CHANGELOG.md` 与对应版本 `Release.zh.md`

---

## 免责声明

本仓库为社区维护的汉化整合版本，不代表上游官方发布。若你用于生产或长期环境，请自行评估兼容性与风险。

---

## 致谢

- 上游作者与贡献者：[`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
- 汉化 / 整合贡献者：[`TIANLI0`](https://github.com/TIANLI0)、本仓库维护者及社区用户

---

## 许可证

MIT，详见 [LICENSE](LICENSE)。
