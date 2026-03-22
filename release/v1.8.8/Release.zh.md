# OpenClaw Android 中文版 v1.8.8

独立 Android 应用，无需单独安装 Termux。

## 本次更新

- 新增首页 OpenClaw 版本显示，并支持检查更新、显示最新版本、直接更新。
- 更新流程会自动检测 npm 最新 `openclaw` 版本与 Node.js 版本要求，不满足时自动升级内置 Node.js 后再更新 OpenClaw。
- 新增“修改配置文件”页面，可直接编辑 `openclaw.json`，支持 JSON 校验、格式化、保存和语法高亮。
- 新增“常用命令”页面，内置常见 OpenClaw 命令，支持一键复制。
- 日志页面支持切换查看“网关日志”和“对话日志”；对话日志读取 `/root/.openclaw/agents/main/sessions/` 下最新的 `.jsonl` 文件。
- 网关按钮新增“启动中 / 停止中”状态；停止时会主动清理残留进程，减少“已经在运行”的误判。
- 修复自定义提供商配置后可能因 `gateway.mode` 未设置而导致网关启动失败的问题。
- 安装向导显示 OpenClaw 预计安装大小，作者名统一为 `JunWan`。

## 下载文件

| 文件 | 适用设备 | 大小 | 下载 |
|---|---|---:|---|
| `OpenClaw-v1.8.8-universal.apk` | 不确定架构时优先下载 | 43.48 MB | [点击下载](./OpenClaw-v1.8.8-universal.apk) |
| `OpenClaw-v1.8.8-arm64-v8a.apk` | 大多数现代 Android 手机 | 26.82 MB | [点击下载](./OpenClaw-v1.8.8-arm64-v8a.apk) |
| `OpenClaw-v1.8.8-armeabi-v7a.apk` | 较老的 32 位 ARM 设备 | 26.44 MB | [点击下载](./OpenClaw-v1.8.8-armeabi-v7a.apk) |
| `OpenClaw-v1.8.8-x86_64.apk` | 模拟器或 x86_64 设备 | 27.03 MB | [点击下载](./OpenClaw-v1.8.8-x86_64.apk) |
| `OpenClaw-v1.8.8.aab` | 应用商店分发 | 50.30 MB | [点击下载](./OpenClaw-v1.8.8.aab) |

## 升级提示

1. 如果你已经安装旧版本，建议直接覆盖安装 `v1.8.8`。
2. 升级后建议先打开应用，等待首页状态恢复，再重新启动一次 Gateway。
3. 如果你此前配置过自定义提供商，可以进入“修改配置文件”确认 `gateway.mode` 已为 `local`。

## 首次运行

1. 安装 APK。
2. 按向导完成初始化，下载 Ubuntu RootFS，并安装基础包、Node.js 与 OpenClaw。
3. 在首页启动 Gateway。
4. 点击首页地址，或在浏览器访问 `http://127.0.0.1:18789` 打开 Web 控制台。

## 系统要求

- Android 10+（API 29 及以上）
- 首次安装建议预留至少 500 MB 可用空间
- 首次初始化需要联网

## 文件校验（SHA256）

- `OpenClaw-v1.8.8-universal.apk`: `322A151E8EF05F531D1131B52BF341A183A18AB3DD9AF9506C6F0B843A0778B0`
- `OpenClaw-v1.8.8-arm64-v8a.apk`: `44830DFBA3F50F70689AC58A0EAD662335F625E34B984B583AE781EBA0F8CCFD`
- `OpenClaw-v1.8.8-armeabi-v7a.apk`: `24EC9978B88C19E494EBD752FB2DD7371E5C37DE29926F99932B4B05670115BE`
- `OpenClaw-v1.8.8-x86_64.apk`: `FA854891878D9520F7A6C87B5047E901A0562C67F81D4D21E49D350AD6A7C8C1`
- `OpenClaw-v1.8.8.aab`: `C10C43FB67D354A8CC13C14A026C100BA5B8C891479DDA913629475325DB34F3`
