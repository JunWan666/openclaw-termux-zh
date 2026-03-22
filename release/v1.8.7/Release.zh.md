# OpenClaw Android 中文版 v1.8.7

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 新增“自定义 OpenAI 兼容”AI 提供商，可填写 API 基础地址、API Key 与自定义模型名，方便接入各类兼容 OpenAI API 的服务。
- 优化网关日志展示：移除 ANSI 颜色控制符，统一显示为更直观的 `YYYY-MM-DD HH:mm:ss` 时间格式，并收敛部分 PRoot 启动 warning。
- 首页快捷操作调整为将“AI 提供商”放在首位，并新增“接入消息平台”入口。
- 新增飞书（Feishu）消息平台配置页，按照官方 `channels.feishu` 配置结构写入，并支持自动迁移旧的错误 `channels.lark` 配置。
- 飞书插件启用后，可在网关启动阶段自动完成插件启用与配置修正，减少手动执行 `doctor --fix` 的成本。

## 下载文件

| 文件 | 说明 |
|---|---|
| `OpenClaw-v1.8.7-arm64-v8a.apk` | 大多数现代 Android 手机（推荐） |
| `OpenClaw-v1.8.7-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 |
| `OpenClaw-v1.8.7-x86_64.apk` | 模拟器或 x86_64 设备 |
| `OpenClaw-v1.8.7-universal.apk` | 全架构通用包（体积更大） |
| `OpenClaw-v1.8.7.aab` | Android App Bundle（用于应用商店分发） |

## 首次运行

1. 安装 APK。
2. 按向导完成初始化，下载 Ubuntu RootFS，并安装基础包、Node.js 和 OpenClaw。
3. 在首页启动 Gateway。
4. 在浏览器访问 `http://127.0.0.1:18789` 打开 Web 控制台。

## 系统要求

- Android 10+（API 29 及以上）
- 首次安装建议预留约 500MB 可用空间
- 首次初始化需要联网

## 文件校验（SHA256）

- `OpenClaw-v1.8.7-arm64-v8a.apk`: `7FF1708A02B7652540CB5156C8449E7912089D98EC51F373C579210A858F9E59`
- `OpenClaw-v1.8.7-armeabi-v7a.apk`: `41ED3A35E79370FDB7ABC213C51F148C183718775CB6358C6894982976881AAD`
- `OpenClaw-v1.8.7-x86_64.apk`: `F750BCE9C18A0D68F5B27EEECDB969AB16DD91A62CFB83779629B55CB23C248F`
- `OpenClaw-v1.8.7-universal.apk`: `B3E728A8316D9BF5115DEC8583F6FB2B5785962DBCF76343DA8851C2823B0C94`
- `OpenClaw-v1.8.7.aab`: `F5B2A1A19067F6F8828394F1CB46ECA964CA8E0F15AB30A6096464AA07B4CA7E`
