# OpenClaw Android v1.8.5（中文版）

独立 Android 应用，无需单独安装 Termux。

## v1.8.5（中文整合版）

本版本基于上游 `mithun50/openclaw-termux`，整合 `TIANLI0` 的 `feature/translation` 分支并做中文维护。

### 主要更新

- 完成中文主文档重构，新增英文文档并支持中英文切换
- 整合 i18n 相关改动（简中/繁中/日文）
- 统一版本为 v1.8.5（Changelog 与项目版本同步）
- 修改 Android 包名，避免与上游官方英文版冲突

### 兼容与注意事项

- 新包名：`com.junwan666.openclawzh`
- 可与官方版本并存安装
- 首次安装请按引导完成环境初始化（rootfs 下载与解压）

### 来源说明

- 上游项目：`mithun50/openclaw-termux`
- 汉化分支：`TIANLI0/openclaw-termux` `feature/translation`

## 下载

| 文件 | 说明 |
|---|---|
| `OpenClaw-v1.8.5-arm64-v8a.apk` | 大多数现代 Android 手机（推荐） |
| `OpenClaw-v1.8.5-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 |
| `OpenClaw-v1.8.5-x86_64.apk` | 模拟器 / x86_64 设备 |
| `OpenClaw-v1.8.5-universal.apk` | 全架构通用包（体积更大） |
| `OpenClaw-v1.8.5.aab` | Android App Bundle（应用商店分发） |

## 首次运行

1. 安装 APK。
2. 按引导完成初始化（会下载约 500MB 的 Ubuntu rootfs）。
3. 在仪表盘中启动 Gateway。
4. 访问 `http://127.0.0.1:18789` 打开 Web 控制台。

## 系统要求

- Android 10+（API 29）
- 首次初始化建议预留约 500MB 可用空间
- 首次运行需要联网
