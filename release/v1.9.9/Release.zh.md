# OpenClaw Android 中文版 v1.9.9

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 维护页新增双导出模式：可以只导出 `openclaw.json` 配置文件，也可以导出带标识的工作目录备份 ZIP，用于迁移 `/root/.openclaw` 下的核心数据。
- 导入链路改为自动识别：配置 JSON、旧版快照 JSON、工作目录 ZIP 都可以直接选择，应用会根据文件内容自动判断恢复意图。
- 工作目录恢复加入安全边界：恢复前会先停止网关，并校验压缩包标识、内部条目和路径范围，只允许恢复 `/root/.openclaw` 白名单路径，避免无边界覆盖整个 rootfs。
- 安装向导完成页也同步支持新的备份导入流程，首次安装后恢复历史配置、记忆和会话上下文更直接。
- 正式发布元数据已同步到 `v1.9.9`，Android 构建号递增到 `44`，用于本次正式打包与发布。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.9.9-universal.apk` | 不确定架构时优先下载 | 100.34 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-universal.apk) |
| `OpenClaw-v1.9.9-arm64-v8a.apk` | 大多数现代 Android 手机 | 83.24 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-arm64-v8a.apk) |
| `OpenClaw-v1.9.9-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 82.88 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-armeabi-v7a.apk) |
| `OpenClaw-v1.9.9-x86_64.apk` | 模拟器或 x86_64 设备 | 83.45 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-x86_64.apk) |
| `OpenClaw-v1.9.9.aab` | 应用商店分发 | 107.14 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9.aab) |

## 升级提示

1. 本次正式版使用 Android 构建号 `44`，可以覆盖安装此前的正式包。
2. 如需迁移模型配置、渠道配置等轻量数据，优先使用“导出配置文件”；如需同时迁移记忆、Agent、技能和会话沉淀，使用“导出工作目录备份”更合适。
3. 工作目录恢复不会导入整个 rootfs，只会恢复 `/root/.openclaw` 白名单路径；如果压缩包不是应用生成的备份，或内部路径越界，导入会被拒绝。
4. 导入前应用会先停止网关；恢复完成后，建议重新检查模型提供商、消息渠道、插件和自定义扩展配置是否符合当前环境。
5. 旧版快照 JSON 仍然可以导入；如果跨版本恢复时出现兼容性确认提示，建议先阅读提示内容后再继续。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，可先选择目标 OpenClaw 版本，再点击“开始安装”。
3. 按向导完成 Ubuntu RootFS、基础包、Node.js 24 与 OpenClaw 的初始化。
4. 配置 API Key、模型提供商与消息渠道。
5. 如需恢复历史环境，可在安装向导完成页或设置页“维护”中直接导入配置文件、旧快照或工作目录备份。
6. 启动 Gateway，并点击首页地址打开 Web 控制台。

## 文件校验（SHA256）

- `OpenClaw-v1.9.9-universal.apk`: `39DD0161FBC99F87ACBF8A3CF90F7635635BF4F9E3033FDBC6F0760798B889B7`
- `OpenClaw-v1.9.9-arm64-v8a.apk`: `1BE83BE6D239E2EE3B7DFE055D02786B754AA29C33A0EE36B45254BFC5F9F5C7`
- `OpenClaw-v1.9.9-armeabi-v7a.apk`: `42467D09F04D8070BC9F9F988BC31781F25020057B5788F0B79D25114A0CB8D5`
- `OpenClaw-v1.9.9-x86_64.apk`: `4A3DE65AE0FAD0C215BC695AF22D31838C8C5B8217A3578030E03AD3059E4605`
- `OpenClaw-v1.9.9.aab`: `8505C990A98F1E52BC9FB671BD0EB66DCB269F4CE1C91D89878518888E2D248E`
