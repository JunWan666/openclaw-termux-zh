# OpenClaw Android 中文版 v3.0.1

v3.0.1 是基于 v3.0.0 内置运行环境版本的正式维护更新，重点调整 AI 提供商首次配置、消息平台插件安装流程，并修复本地模型运行时下载。

版本信息：

- `versionName`：`3.0.1`
- 基础构建号：`82`
- ARM64 APK 实际 `versionCode`：`2082`
- 包名：`com.junwan666.openclawzh`
- 最低系统：Android 10
- 发布架构：ARM64 (`arm64-v8a`)

## 重点更新

- 首次初始化默认引导配置 DeepSeek 官方 API，不再内置可直接使用的第三方 API Key。
- `7749API（ywd 公益）` 更新为 `open7749` 新端点和模型，并自动迁移旧提供商 ID、模型引用、allowlist 与用户已有 API Key。
- QQ 机器人和微信插件不再自动检测或安装，改为由用户手动检测和显式启动安装。
- 新增 QQ 机器人插件终端安装页；保存 QQ 配置不会再隐式安装插件。
- 微信安装器根据真实进程退出码返回成功或失败。
- llama.cpp 最新稳定 Release 没有 Ubuntu 二进制包时，会继续扫描近期滚动版本，再使用固定回退版本。
- 本地模型页面优先展示运行时安装入口和安装日志，简化顶部提示。

## 下载

| 文件 | 适用设备 | 大小 |
|---|---|---:|
| `OpenClaw-v3.0.1-arm64-v8a-full.apk` | Android 10+ ARM64 手机和平板 | 331.91 MiB |

本版本仅发布 ARM64 完整版，不发布 Universal、ARMv7、x86_64 APK 或 AAB。

## 升级说明

- v3.0.0 用户可直接覆盖安装 v3.0.1，两个版本使用相同的长期正式签名。
- 2.x 使用旧签名，不能直接覆盖安装。请先导出备份，再卸载旧版、安装 v3.0.1 并导入备份。
- 升级前仍建议备份 `/root/.openclaw` 中的重要配置和工作区数据。

## 验证情况

- Flutter 自动化测试：142 项通过。
- Node 自动化测试：11 项通过。
- Dart 静态分析：无 error 或 warning；存在 12 条既有 info 提示。
- Android ARM64 Release 构建：通过。
- APK 签名验证：通过，使用 APK Signature Scheme v2。
- zipalign 对齐验证：通过。

## 文件校验

`OpenClaw-v3.0.1-arm64-v8a-full.apk`

```text
SHA-256: 07046F5576944E253B98F7895680A7720B29C50FBA5077B1B854B93537867EBF
```

正式签名证书：

```text
SHA-256: 9A:F4:9F:37:47:A2:A2:90:CE:18:7A:61:D2:EE:EE:31:5D:50:EC:B4:58:05:2A:68:4B:AB:C2:18:52:8C:C1:61
```
