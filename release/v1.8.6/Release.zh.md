# OpenClaw Android 中文版 v1.8.6

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 安装向导进度显示更细化：RootFS 解压、基础包安装、Node.js 处理和 OpenClaw 安装阶段现在会显示更平滑的步骤百分比，减少长时间看起来“卡住不动”的情况。
- 日志页面新增“清空日志”按钮，并带确认弹窗；该操作只会清空应用内日志列表，不会删除磁盘上的日志文件。
- 修复节点 WebSocket 心跳实现，改为底层 ping 帧，不再发送纯文本 `ping`，从而避免网关侧的 JSON 解析错误。
- 优化 PRoot 标准输入输出绑定逻辑，仅在 `/proc/self/fd/0/1/2` 实际可绑定时才进行绑定，从而减少部分设备上的启动 warning。
- 新增 Python 发布构建脚本，可交互输入版本号和构建号，并自动将 APK / AAB 整理到 `release/v1.8.6/` 目录。

## 下载文件

| 文件 | 说明 |
|---|---|
| `OpenClaw-v1.8.6-arm64-v8a.apk` | 大多数现代 Android 手机（推荐） |
| `OpenClaw-v1.8.6-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 |
| `OpenClaw-v1.8.6-x86_64.apk` | 模拟器或 x86_64 设备 |
| `OpenClaw-v1.8.6-universal.apk` | 全架构通用包（体积更大） |
| `OpenClaw-v1.8.6.aab` | Android App Bundle（用于应用商店分发） |

## 首次运行

1. 安装 APK。
2. 按向导完成初始化，下载 Ubuntu RootFS，并安装基础包、Node.js 和 OpenClaw。
3. 在首页启动 Gateway。
4. 在浏览器访问 `http://127.0.0.1:18789` 打开 Web 控制台。

## 系统要求

- Android 10+（API 29 及以上）
- 首次安装建议预留约 500MB 可用空间
- 首次初始化需要联网
