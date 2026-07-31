# OpenClaw 2026.7.x 回归记录

## 1. 环境与基线

- 日期：2026-07-31。
- App：`v2.0.2`，Android `versionCode 77`。
- 主环境：x86_64 API 35 模拟器 `OpenClaw_API_35`。
- Stable：`2026.3.23`。
- Experimental：npm `latest`，验证时为 `2026.7.1-2`。
- Node.js：arm64/x86_64 固定 `24.18.1`；armv7 固定 `22.22.2`。

## 2. 自动化门禁

| 项目 | 结果 |
| --- | --- |
| 版本通道、semver、Node engines 专项测试 | 13 项通过 |
| 协议、恢复、配置迁移与 doctor 专项测试 | 31 项通过 |
| Flutter 全量测试 | 106 项通过 |
| `flutter analyze` | 无 error/warning；仅保留升级前已有的 12 条 info |
| x86_64 Debug APK | 构建成功，`99,059,227` bytes |
| npm 在线元数据 | `latest=2026.7.1-2`，Node 范围为 `>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0` |

## 3. x86_64 模拟器回归

### 3.1 版本通道

- 在线列表首项为 Stable `2026.3.23`，第二项为 Experimental `2026.7.1-2`，其余 beta/revision 版本标记为历史版本。
- 离线场景仍显示 Stable 与本机已安装版本，并提供重试入口。
- 选择 Stable 时，确认框正确显示：当前 `2026.7.1-2 (Experimental)`、目标 `2026.3.23 (Stable)`、保护性快照、失败回滚、7.x 状态保留及旧版可能忽略新字段的说明。
- 在确认框取消后未启动安装，随后恢复选择 Experimental。

### 3.2 APK 覆盖安装与数据保护

APK 使用 `adb install -r` 覆盖安装，安装前、安装后、启动后、通道选择和确认取消后的保护文件 SHA-256 均一致：

```text
openclaw.json                  47175446aec4b69a0b2a4666bb7e2db1e8efb8d39ba090d4da34af967f916e0c
FlutterSharedPreferences.xml  785a7e0912bfc17b6e114470a53d7c8ab5e520a200a9345bf87da64fb8d1da57
```

### 3.3 Latest Gateway

- `2026.7.1-2` 在 x86_64 模拟器冷启动约 165 秒后进入“运行中”。
- 2026-07-31 在原主模拟器再次复验，约 40 秒进入“运行中”；`openclaw-gateway` 进程和 18789 IPv4/IPv6 loopback 监听正常。
- `127.0.0.1:18789` 与 IPv6 loopback 均进入 LISTEN，健康探测连接成功。
- 冷启动期间可以主动点击“停止网关”；PRoot/OpenClaw 进程可清理，UI 返回“已停止”。
- 正常运行态停止后，无 `libproot`、`openclaw`、`openclaw-gateway` 进程和 18789 LISTEN socket 残留。
- 启停前后保护文件 SHA-256 保持一致。

### 3.4 安装中断恢复入口

- 在独立空白 x86_64 API 35 AVD 上选择 Stable `2026.3.23`，确认首次安装从 RootFS、基础包、Node.js `24.18.1` 进入 OpenClaw 包安装阶段。
- OpenClaw 包安装约 95.8% 时重启 AVD，模拟设备或进程被终止；重启后应用没有进入首次安装或 Dashboard，而是识别为 `upgradeInterrupted` 并进入“环境恢复”页。
- 恢复页提供重新检测、打开终端和导出备份，不提供一键删除或自动重装，符合数据保护约束。
- 本场景覆盖安装进程被终止后的识别与安全路由，不等同于真实网络断开，也未形成 Stable/Latest 完整全新安装通过证据。
- 按当前机器内存约束，临时 AVD 在取证后已删除，后续仅运行原始中文主模拟器；主环境和第二个既有 AVD 的数据未清理。

### 3.5 复用的前序真实回归证据

- Stable `2026.3.23` Gateway、Pair、Android Node v3 调用已通过。
- Latest `2026.7.1-2` Gateway、Pair、scope、Android Node v4 调用已通过。
- 已完成 `Latest → Stable → Latest`，升级事务为 `committed`，doctor lint/fix、Provider、Session 与 SQLite 完整性通过。
- 已真实注入 npm `EEXIST` 失败并自动回滚；配置、SQLite、device pair 与 SharedPreferences 哈希保持一致。
- wrapper/symlink、Bionic Bypass、Node wrapper 缺失可自动修复；存在用户数据但 package.json 缺失时进入人工恢复而非首次安装。
- 自定义 Provider Base URL 保存、重新进入编辑页和容器配置读取均保持原值，不追加 `/v1`。

### 3.6 升级事务中断自动化补强

- 启动状态现在读取非终态升级事务 ID；只有真实升级事务存在时才自动回滚，普通首次安装中断仍进入人工恢复页。
- 事务清单在第一次 package 移动前落盘，并记录 `packageInstalled / doctorChecked / configMerged / verified` 阶段及脱敏详情；`committed / rolledBack` 不会被误判为待恢复事务。
- 回滚仅在 package 备份确实存在时替换当前 package；若清单已写但移动尚未发生，会保留原 package；备份和原 package 同时缺失时停止并转人工恢复。
- 自动化覆盖事务刚创建但尚无 npm 残留、回滚成功、回滚失败保护、重复修复幂等、v3/v4 Invoke fixture、数组保序和敏感字段新增/删除脱敏。本节为单元测试与构建证据，尚未替代真实设备升级断电回滚。

## 4. 回归矩阵结论

| 矩阵 | 状态 | 说明 |
| --- | --- | --- |
| Stable Gateway/Pair/Node/Sessions | 通过 | 复用阶段一至三的真实回归证据 |
| Latest Gateway/Pair/Node/Provider/Sessions | 通过 | 本阶段重新执行 Gateway 启停；其余复用前序证据 |
| Stable/Experimental 在线与离线版本选择 | 通过 | 自动化与模拟器均覆盖 |
| Stable → Latest → Stable → Latest | 通过 | 数据保护和事务幂等已验证 |
| 故障注入 | 部分通过 | npm 中断、安装阶段重启、wrapper、bypass、完成标记、doctor 和非终态事务回滚自动化已覆盖；真实网络断开与真实升级断电回滚尚未执行 |
| 非空 Goals 前后内容比对 | 未覆盖 | 当前模拟器 Goals/commitments 数据集为空，仅验证数据库结构、保护路径与 `integrity_check=ok` |
| arm64 真机 | 未覆盖 | 当前工作环境仅连接 x86_64 API 35 模拟器，需要外部真机完成安装、Gateway、Control UI、Pair 和 Node 冒烟 |
| 旧 WebView 真机 | 未覆盖 | 应单独记录浏览器内核限制，不使用协议降级掩盖 |

## 5. 已知限制与后续建议

- x86_64 模拟器上的 Latest Gateway 冷启动约 165 秒，明显长于常规健康探测宽限期；UI 现在允许在启动中安全停止。真机应单独记录冷启动耗时并评估是否需要持久化“仍在启动”的进度提示。
- 使用包含非空 Goals/commitments 的 7.x 样本重复执行升级/回滚内容比对。
- 在 arm64 真机完成安装、Gateway、Control UI、Pair 与 Android Node 冒烟后，再把设备矩阵标记为完整。
- 当前机器按要求仅运行原始中文主 AVD。Stable/Latest 完整全新安装和真实下载中断仍需在允许清空数据的测试窗口或外部可丢弃设备执行，不在保留用户数据的主环境中清空 App 数据。
