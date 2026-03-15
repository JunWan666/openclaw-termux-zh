# MobileOpenClaw （基于 openclaw-termux-zh）

[简体中文](README.md) | [English](docs/README_en.md)

> 本仓库为自用优化版本，主要用于大陆用户实现手机部署openclaw，claudecode等。
>
> 整合来源：
> - 上游项目：[`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - 汉化分支作者：[`TIANLI0/openclaw-termux` 的 `feature/translation` 分支](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)
> - https://github.com/JunWan666/openclaw-termux-zh.git
> 基于上游，本仓库改动：
- 源换为清华源、阿里源等大陆用户方便下载的源，部署过程更迅速，终端用户操作也更便捷。
- 

---

## 项目简介

OpenClaw 是一个在 Android 上运行的 AI Gateway 方案。该项目通过 Flutter + proot Ubuntu 环境，在非 root 设备上提供：

- 一键安装 Ubuntu rootfs + Node.js + OpenClaw
- 应用内终端、日志、Web 控制台
- 网关管理与健康检查
- 可选工具包（如 Go、Homebrew、OpenSSH）
- 节点能力接入（相机、位置、传感器等）

<p align="center">
  <img src="assets/ic_launcher.png" alt="OpenClaw" width="180"/>
</p>

---


## 主要特性（中文整合版）

- 中文优先文档与维护流程
- i18n 文案与页面整合（含简中/繁中/日文）
- 保留上游核心功能与结构，便于后续同步
- 版本变更统一在 Changelog 中记录

---

## 快速开始

### 方式一：Android APK（推荐）

1. 从本仓库 Releases 下载 APK（如你已发布）
2. 安装后打开应用
3. 点击 **Begin Setup** 完成环境初始化
4. 在应用内完成 Onboarding 与 API Key 配置
5. 启动 Gateway

---

## 目录说明

- `flutter_app/`：Flutter Android 主应用
- `lib/`：Node/CLI 相关脚本
- `scripts/`：构建与依赖准备脚本
- `docs/README_en.md`：英文文档
- `CHANGELOG.md`：版本与改动记录
---

## 免责声明

本仓库为社区维护的汉化整合版本，不代表上游官方发布。若你用于生产或长期环境，请自行评估兼容性与风险。

---

## 致谢

- 上游作者与贡献者：[`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
- 汉化/整合贡献者：[`TIANLI0`](https://github.com/TIANLI0)、本仓库维护者及社区用户

---

## 许可证

MIT，详见 [LICENSE](LICENSE)。
