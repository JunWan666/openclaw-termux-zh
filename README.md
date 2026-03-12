# OpenClaw 中文整合版（openclaw-termux-zh）

[简体中文](README.md) | [English](docs/README_en.md)

> 本仓库为汉化整合版本，主要用于中文用户维护与分发。
>
> 整合来源：
> - 上游项目：[`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - 汉化分支作者：[`TIANLI0/openclaw-termux` 的 `feature/translation` 分支](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)
>
> 本仓库在上游基础上整合了 i18n（简中/繁中/日文）相关改动，并以中文文档为主。

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

## 当前版本

- 版本：`v1.8.6`
- 主要变更：见 [CHANGELOG.md](CHANGELOG.md)

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

### 方式二：源码构建

```bash
git clone https://github.com/JunWan666/openclaw-termux-zh.git
cd openclaw-termux-zh/flutter_app
flutter pub get
flutter build apk --release
```

说明：如果你需要可运行的 proot 相关 `.so`，请按仓库脚本准备 `jniLibs` 后再打包。

推荐：也可直接使用仓库内的 Python 发布脚本，它会交互输入版本号/构建号，并自动将 APK/AAB 整理到 `release/v版本/` 目录：

```bash
python scripts/build_release.py
```

---

## 目录说明

- `flutter_app/`：Flutter Android 主应用
- `lib/`：Node/CLI 相关脚本
- `scripts/`：构建与依赖准备脚本
- `docs/README_en.md`：英文文档
- `CHANGELOG.md`：版本与改动记录

---

## 与上游同步建议

如果后续要继续跟进上游更新，建议流程：

1. 同步上游 `main`
2. 在独立分支处理冲突
3. 回归测试（安装、rootfs 解压、网关启动）
4. 更新本仓库 `CHANGELOG.md`

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
