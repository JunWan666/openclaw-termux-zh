# OpenClaw Android 中文版 v2.0.1

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 修复 AI 提供商页里“自定义模型”会串到其他提供商的问题；现在每个提供商都会保留自己的模型选择和自定义模型值，避免切换渠道后把别家的模型名误带过去。
- 修复对话日志读取时再次触发 `config/resolv.conf` 缺失的老问题；日志页现在直接读取应用工作目录中的 `.jsonl` 会话文件，不再为了看日志额外走一层 PRoot 命令执行。
- 首页快捷操作新增“本地模型和对话”与“备份中心”；日志快捷入口默认隐藏，入口层级更适合手机上直接操作。
- 本地模型能力补齐为完整链路：可安装官方 `llama.cpp` 运行时、浏览内置 GGUF 模型列表、联网搜索公开 GGUF、下载 Gemma 4 等热门模型、查看中文大白话建议，并管理已安装模型。
- 本地对话页升级为直接可用的调试台：支持流式输出、思考开关、思考内容预览、Markdown 渲染、停止生成、折叠头部、内存占用展示、API 地址复制，以及切换本地模型、已保存配置或手动填写接口。
- 本地模型资源设置更适合手机使用：支持 CPU 核心数、内存软限制和性能模式设置；内存限制改为按 GB 输入，并补充更直白的性能说明。
- 备份入口升级为统一的“备份中心”，可导入外部备份、保存当前配置到备份库、切换和恢复已保存备份，并继续导出配置备份或工作目录备份。
- 正式发布元数据已重新收口到 `v2.0.1`，Android 构建号提升到 `68`，用于本次重新打包与发布。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v2.0.1-universal.apk` | 不确定架构时优先下载 | 102.06 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-universal.apk) |
| `OpenClaw-v2.0.1-arm64-v8a.apk` | 大多数现代 Android 手机 | 83.80 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-arm64-v8a.apk) |
| `OpenClaw-v2.0.1-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 83.53 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-armeabi-v7a.apk) |
| `OpenClaw-v2.0.1-x86_64.apk` | 模拟器或 x86_64 设备 | 84.01 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-x86_64.apk) |
| `OpenClaw-v2.0.1.aab` | 应用商店分发 | 108.84 MB | [点击下载](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1.aab) |

## 升级提示

1. 本次正式版使用 Android 构建号 `68`，可以覆盖此前的 `2.0.x` 正式包与最近的测试包。
2. 如果此前在 AI 提供商页面使用过“自定义模型”，升级后建议切到各个提供商检查一遍模型名，确认都已经恢复到各自独立配置。
3. 如需使用手机本地模型，建议优先选择量化后的 1B-4B GGUF 模型；设备内存更高时，再尝试 7B-8B 级别模型或 Gemma 4 主力档。
4. 本地对话页现在可以先进去，再决定是连接手机本地模型、切到已保存 Provider，还是手动填写一个接口。
5. 备份中心会把导入进来的备份保存在本地库里，后面想切换或恢复时不用再重复找文件。

## 首次运行

1. 安装 APK。
2. 首次进入安装页时，确认目标 OpenClaw 版本，再点击“开始安装”。
3. 按向导完成 Ubuntu RootFS、基础包、Node.js 24 与 OpenClaw 的初始化。
4. 如需使用手机本地模型，可从首页快捷操作进入“本地模型和对话”，安装 `llama.cpp` 运行时并下载 GGUF 模型。
5. 配置 API Key、模型提供商，或在本地模型页一键启用本地 Provider 预设。
6. 启动 Gateway，并点击首页地址打开 Web 控制台。

## 文件校验（SHA256）

- `OpenClaw-v2.0.1-universal.apk`: `ED30BD54FD546F0B320D41F46FE4F7666DD9D543A750AA681E04E7F243CE4F74`
- `OpenClaw-v2.0.1-arm64-v8a.apk`: `E7E013111A29035E9670FA1200D9A7DBC1DA71B863F13C5B63D5ED90906129D9`
- `OpenClaw-v2.0.1-armeabi-v7a.apk`: `45C0A286D5AE708C439FE97FC6752B8160C831CCBD2FCBCDAB47A8D8003B13A9`
- `OpenClaw-v2.0.1-x86_64.apk`: `CC4F8F49EA851F60B185E5CAB09FB64E056614607AB316191683F8AC8FC03361`
- `OpenClaw-v2.0.1.aab`: `52D1AC17D04A835BDA4338F4EA5DD52E365DABA6135E00D677A03ED158F15BEA`
