# OpenClaw 2026.7.x 兼容升级实施计划

## 1. 实施原则

- 稳定优先，`2026.3.23` 始终作为 Stable 保留。
- 不重写现有安装流程，只增加兼容层、恢复层和迁移编排。
- 保留现有 UI 和用户操作路径。
- 所有新增业务代码使用中文注释。
- 不修改无关代码，不整理无关格式，不覆盖当前未提交改动。
- 每一阶段单独完成测试、构建和证据记录；未通过不得进入下一阶段。
- 所有破坏性操作默认禁止；任何升级失败都必须优先保护 RootFS 和 `/root/.openclaw`。

## 2. 阶段门禁

每个编码阶段统一执行：

1. 记录阶段开始前 `git diff --stat` 和相关文件 diff。
2. 先补充失败测试或协议 fixture。
3. 实现最小范围修改。
4. 执行 `dart format`，只格式化本阶段涉及文件。
5. 执行相关单元测试。
6. 执行全部 `flutter test`。
7. 执行 `flutter analyze`，结果不得新增 error/warning/info。
8. 构建 `flutter build apk --debug --target-platform android-x64`。
9. 在模拟器执行本阶段运行时场景。
10. 保存测试结果和已知限制，更新实施计划状态。

## 3. 阶段一：Gateway Protocol v4

### 3.1 目标

- `2026.3.23` 继续连接。
- `2026.7.x` 优先使用 v4。
- 明确支持协议协商和安全降级。
- 将未来协议升级限制在独立协议层，不再散落修改 Service。

### 3.2 模块设计

拟新增：

- `GatewayProtocolVersionRange`：客户端支持范围和协商结果。
- `GatewayHello`：解析 hello-ok 的 protocol、auth、policy、features、sessionDefaults。
- `GatewayAuthState`：区分 shared token、device token 和无认证来源。
- `GatewayErrorInfo`：解析 code、message、details、reason、recommendedNextStep、retryAfterMs。
- `GatewayConnectDecision`：决定重试、暂停、deviceToken 重试或协议降级。

拟调整：

- `node_frame.dart`：保持通用帧，不在模型名中绑定 v3。
- `node_ws_service.dart`：支持服务端建议延时、可暂停重连、连接预算和确定性错误。
- `node_identity_service.dart`：签名载荷保持向后兼容，协议版本由协商层决定。
- `node_service.dart`：只负责编排，不直接堆叠协议判断。
- `preferences_service.dart`：设备 Token 存储增加 endpoint/role/scopes 元数据，同时兼容旧单字符串 Token。

### 3.3 协商策略

1. 初始连接声明实现确认安全的范围。
2. 读取服务端 hello-ok 的协商协议。
3. 如果返回明确 protocol mismatch：
   - 2026.3.23 降级到 v3。
   - 2026.7.x 使用 v4。
4. Auth、Scope、Token 错误不得触发协议降级。
5. deviceToken 重试最多一次，防止循环。
6. `retryAfterMs` 仅在总连接预算内生效。
7. 确定性鉴权失败暂停自动重连，等待 Token/Pair 状态变化。

### 3.4 测试

- v3 challenge/connect/hello-ok fixture。
- v4 challenge/connect/hello-ok fixture。
- v3 服务端协议拒绝后的安全降级。
- v4 协商成功。
- Auth token mismatch → deviceToken 单次重试。
- deviceToken 失败 → 清理对应 Token 并暂停。
- `retryAfterMs` 延迟重试。
- scopes、sessionDefaults、policy、features 解析。
- 未知字段不导致解析失败。
- Node invoke v3/v4 均可响应。

### 3.5 阶段通过标准

- 新增协议单测全部通过。
- 全部 Flutter 测试通过。
- analyze 不增加提示。
- x86_64 Debug APK 构建成功。
- 模拟器分别连接 Stable 和 Latest Gateway，Node Pair/Invoke 通过。

## 4. 阶段二：升级恢复能力

### 4.1 目标

- 不再以一个 Boolean 表示整个环境状态。
- 旧容器或升级中断时优先进入修复模式。
- 自动修复仅处理可重建运行文件，不触碰用户数据。

### 4.2 状态模型

新增环境检查结果：

```text
fresh
complete
repairable
upgradeInterrupted
manualRecoveryRequired
```

检查项：

- RootFS、bash、Node。
- OpenClaw package.json 和实际版本。
- OpenClaw wrapper/symlink。
- Node wrapper、proot compat、Bionic Bypass。
- `openclaw.json`、`.env`、agents/data/memory 等用户数据存在性。
- Gateway 进程和端口健康状态。
- npm 安装/升级残留。

### 4.3 修复顺序

```text
检测现有环境
  ├─ 完整且 openclaw --version 成功 → Dashboard
  ├─ 可修复
  │   ├─ 停止残留安装进程（不停止健康 Gateway）
  │   ├─ setupDirectories
  │   ├─ createBinWrappers(openclaw)
  │   ├─ installBionicBypass
  │   ├─ writeResolv
  │   └─ openclaw --version
  │       ├─ 成功 → Dashboard
  │       └─ 失败 → 手动恢复页面
  ├─ 已有 Gateway 正在运行 → Dashboard + 修复提示
  ├─ 用户数据存在但核心不可运行 → 手动恢复页面
  └─ 真正空环境 → 首次安装
```

### 4.4 UI

- 保持现有安装页风格。
- 增加“正在修复现有环境”状态，不新增复杂导航。
- 修复失败提供：重试修复、打开终端、导出备份；不默认提供一键删除重装。

### 4.5 测试

- wrapper 缺失、package.json 保留。
- symlink 缺失。
- bypass 缺失。
- package.json 缺失但用户数据存在。
- Gateway 已运行但完成标记不完整。
- npm 半安装目录存在。
- 修复成功直接进入 Dashboard。
- 修复失败不删除任何保护路径。
- 重复修复幂等。

## 5. 阶段三：配置与状态迁移

### 5.1 目标

- 3.23 升级到 7.x 时保护 Gateway、Token、Pair、Sessions、Goals、Providers 和自定义 URL。
- 不实现一套与 OpenClaw 重复的内部迁移规则。
- 官方迁移前后均可审计和回滚。

### 5.2 升级事务

新增升级事务对象，记录：

- sourceVersion/targetVersion。
- 保护性备份路径和摘要。
- 升级阶段。
- doctor lint/fix 结果。
- 配置结构化 diff。
- 验证与回滚结果。

执行：

1. 停止 Gateway。
2. 导出内部升级备份，不要求用户选择文件。
3. 记录保护路径清单和摘要。
4. 安装目标版本。
5. 验证实际版本。
6. `doctor --lint --json`。
7. 必要时 `doctor --fix --non-interactive`。
8. 校验已有非空字段未被默认值覆盖。
9. 校验保护路径仍存在。
10. 启动 Gateway 并健康检查。
11. 提交升级事务；失败则回滚 package/config。

### 5.3 配置合并规则

- 缺失字段可补默认值。
- 已有非空标量不得被默认值覆盖。
- Map 递归合并。
- 用户数组默认保持原序和内容；除非官方迁移明确转换且通过验证。
- Token、SecretRef、API key 不写入日志和迁移报告。
- 未知字段默认保留。
- 迁移失败保留原配置和 `.bak`。

### 5.4 状态保护验证

- Gateway：mode、bind、auth、controlUi、nodes。
- Token：gateway token、App Preferences、device token。
- Pair：device identity、公私钥、device token/scopes。
- Sessions：Session 索引、转录、SQLite/状态文件。
- Goals：与 Session 绑定的目标状态。
- Providers：models.providers、agents.defaults.model、auth 相关状态。
- 用户目录：memory、skills、extensions、agents、data、config。

### 5.5 测试

- 纯 Dart 配置 merge/diff 测试。
- 敏感字段不出现在日志。
- 旧配置 fixture → 目标配置 fixture。
- doctor lint/fix 模拟结果。
- 迁移失败回滚。
- 备份范围包含真实 7.x Sessions/Goals 存储。
- Stable → Latest → Stable 数据一致性。

## 6. 阶段四：Base URL 修复

### 6.1 目标行为

- OpenAI 内置地址保持 `/v1`。
- OpenRouter 内置地址保持 `/api/v1`。
- 自定义地址完全按用户输入保存，仅去除首尾空白。
- 测试请求可以拼接 endpoint，但不得修改输入框或持久化值。

### 6.2 修改范围

- `BaseUrlBehavior` 增加明确的“内置固定”“自定义保持”语义。
- `normalizeCustomBaseUrl()` 不再追加 `/v1`。
- `migrateCustomProviderConfigIfNeeded()` 不再修改已保存 Base URL。
- 保存页面不在失焦、测试或重载时重写 URL。
- 连接测试服务继续根据 API 类型构建探测 URL。

### 6.3 测试用例

- `https://api.openai.com/v1` 保持。
- `https://openrouter.ai/api/v1` 保持。
- `https://api.lkeap.cloud.tencent.com/plan/v3` 保持。
- `https://example.com` 保持。
- `https://example.com/custom/path/` 除首尾输入空白外保持。
- 读取旧配置不产生写操作。
- 测试成功后再次读取仍为原值。

## 7. 阶段五：版本管理

### 7.1 通道

- Stable：固定 `2026.3.23`，默认推荐。
- Experimental：npm 当前 `2026.7.x` 最新稳定发布。
- 其他历史版本：继续允许选择，但不标记 Stable/Experimental。

### 7.2 行为

- 安装页离线时仍显示 Stable。
- 在线时显示 Experimental 最新版本和 Node 要求。
- 升级/降级前显示来源、目标、通道和数据保护说明。
- 保留现有版本选择布局和按钮。
- 回滚不删除 7.x 新增状态；只切换 package 并提示旧版可能忽略新字段。

### 7.3 版本工具

- 引入完整 semver/版本范围判断，正确处理 `||`、上下界和 prerelease/revision。
- engines 不满足时选择已验证 Node 版本；不得仅取表达式第一个版本号。

## 8. 阶段六：真实回归矩阵

### 8.1 Stable

- 全新安装。
- Gateway 启停和健康检查。
- Pair/Token。
- Control UI。
- Android Node Pair/Invoke。
- Sessions。
- Stable 环境下已有功能回归。

说明：Goals 是 2026.7.x 新能力，Stable 测试应确认旧版不会因 App 新增兼容层而报错，而不是要求旧版提供不存在的功能。

### 8.2 Latest

- 全新安装最新版。
- Gateway 启停。
- Pair/Token/scopes。
- Control UI。
- Sessions/Goals。
- Android Node。
- Providers 和自定义 Base URL。
- doctor lint/post-upgrade。

### 8.3 升级/回滚

- 3.23 创建 Provider、Session、Pair 数据。
- 升级 7.x。
- 验证数据和功能。
- 回滚 3.23。
- 再升级 7.x，验证幂等和数据不丢失。

### 8.4 故障注入

- 升级中终止 npm。
- 删除 wrapper/symlink。
- 删除 bypass。
- 保留 package.json 和 RootFS。
- 损坏 App 完成标记。
- 网络中断。
- doctor 返回 warning/error。

### 8.5 设备范围

- x86_64 API 35 模拟器：自动化主环境。
- arm64 真机：至少完成安装、Gateway、Control UI、Pair、Node 冒烟测试。
- 旧 WebView 设备问题单独记录，不用协议修复掩盖浏览器内核限制。

## 9. 阶段七：代码质量与文档

- 协议、恢复、迁移分别独立模块，避免重复判断。
- 新增代码使用中文注释，公开类型和关键状态机写明不变量。
- README 增加 Stable/Experimental 兼容矩阵。
- README 说明 Node.js `24.18.1`、协议协商和恢复模式。
- CHANGELOG 记录兼容升级，不改写历史发布记录。
- 清理仅限本次新增的 analyze 提示；既有 12 条提示单独记录，不混入无关修复。

## 10. 最终交付物

- 兼容性分析报告。
- 实施计划。
- v3/v4 协议差异总结。
- 协议 fixture 和自动化测试。
- 升级恢复流程及故障注入测试。
- 配置迁移策略和结构化 diff 测试。
- Stable/Experimental 版本管理。
- README/CHANGELOG 更新。
- Stable、Latest、升级、回滚测试记录。
- 尚未解决问题和后续建议。

## 11. 当前阶段状态

- 分析：完成。
- 阶段一 Gateway Protocol v4：完成。Stable `2026.3.23` 已验证 v3，Latest `2026.7.1-2` 已验证 v4、Token、Scope 与 Android Node 配对。
- 阶段二升级恢复能力：完成。新增 `fresh / complete / repairable / upgradeInterrupted / manualRecoveryRequired` 状态模型，并接入启动路由。
- 阶段二自动修复范围：仅重建 OpenClaw command wrapper、Bionic Bypass、Node wrapper、PRoot compatibility 和 DNS 运行文件；不停止健康 Gateway，不删除 RootFS、配置或用户数据。
- 阶段二自动门禁：67 项 Flutter 测试通过；`flutter analyze` 仅保留既有 12 条 info；x86_64 Debug APK 构建成功。
- 阶段二模拟器故障注入：已验证 OpenClaw symlink/command 缺失、Bionic Bypass 缺失、Node wrapper 缺失均可自动修复并直接进入 Dashboard；`package.json` 缺失且用户数据存在时进入人工恢复页，不进入首次安装。
- 数据保护证据：故障注入前后 `openclaw.json` 与 SharedPreferences SHA-256 均保持一致。
- 阶段三配置迁移：完成。升级事务保护 `openclaw.json / data / memory / skills / config / extensions / agents / state / devices / nodes / identity / workspace / canvas / skill-workshop`，成功提交历史报告，任意异常自动回滚 package、command 与工作区。
- 阶段三迁移策略：新版默认字段可以补入；原有非空 Provider、Token、自定义 Base URL 和未知字段优先保留；结构化 diff 不记录敏感值。Latest 的 `doctor --lint --json` 允许以状态码 1 返回检查结果，并在 `ok=false` 时执行一次非交互修复。
- 阶段三真实回归：完成 Latest `2026.7.1-2 → Stable 2026.3.23 → Latest 2026.7.1-2`。Stable Gateway/Node/Pair 正常；Latest 升级事务 `committed`，doctor lint/fix、Gateway、Node、Pair、Provider、Session 和 SQLite 完整性均通过。
- 阶段三异常回滚：真实触发 npm `EEXIST` 后自动恢复 `2026.7.1-2`；`openclaw.json`、SQLite、device pair 与 SharedPreferences 的升级前后 SHA-256 完全一致。随后修复旧 command 未移走的问题并通过成功降级。
- 阶段三自动门禁：71 项 Flutter 测试通过；`flutter analyze` 仅保留既有 12 条 info、无 warning/error；x86_64 Debug APK 构建成功。
- 数据样本限制：模拟器保留 1 个 Session 索引和 8 行转录记录；Goals/commitments 原始数据集为空，因此只验证了相关数据库结构、保护路径和 SQLite `integrity_check=ok`，没有非空 Goal 可做前后内容对比。
- 阶段四 Issue #43 Base URL 修复：完成。内置 Provider 保留各自官方默认路径；自定义 Base URL 只去除首尾输入空白，保存、兼容类型切换和旧配置迁移均不再自动追加 `/v1`；连接测试仅在发起请求时拼接具体 endpoint。
- 阶段四自动门禁：14 项 Provider/Base URL 专项测试与 77 项 Flutter 全量测试通过；`flutter analyze` 仅保留既有 12 条 info、无 warning/error；x86_64 Debug APK 构建成功。
- 阶段四模拟器回归：在 Latest `2026.7.1-2` 运行环境中，将现有自定义 Provider 临时保存为 `https://httpbin.org/anything/stage4-provider`，直接读取容器配置及重新进入编辑页均保持原值、未追加 `/v1`；随后恢复原地址并再次读取配置确认无测试残留。Gateway 与 Node 配对状态保持正常。
- 阶段五版本管理：完成。Stable 固定 `2026.3.23` 并在离线时保留；npm `latest=2026.7.1-2` 作为 Experimental；其他版本标记为历史版本。安装页与首页默认不以 Experimental 替换 Stable。
- 阶段五 semver/Node engines：完成。支持 `||`、上下界、caret、tilde、wildcard、hyphen、prerelease 与数字 revision；仅从已验证的 Node 运行时中选择满足完整范围的版本，armv7 对不满足要求的 Experimental 明确禁用。
- 阶段五模拟器回归：在线版本菜单按 Stable、Experimental、历史版本排序；选择 Stable 后确认框显示来源、目标、通道、保护快照、失败回滚和降级字段兼容提示。取消确认未产生安装或配置写入，随后恢复 Experimental 选择。
- 阶段五自动门禁：11 项版本专项测试与 88 项 Flutter 全量测试通过；`flutter analyze` 仅保留既有 12 条 info、无 warning/error；x86_64 Debug APK 构建成功。
- 阶段六 Latest Gateway：x86_64 API 35 模拟器冷启动约 165 秒后进入运行中，18789 IPv4/IPv6 loopback 监听和健康探测通过；运行态停止后无 PRoot/OpenClaw 进程、前台服务或 LISTEN socket 残留。
- 阶段六启动取消修复：Gateway 冷启动阶段新增可用的“停止网关”按钮；原生清理改为扫描同 UID `/proc` 命令行并匹配 PRoot/OpenClaw Gateway，进程重命名后仍可安全停止。
- 阶段六数据保护：Debug APK 覆盖安装、应用启动、通道选择、确认取消与 Gateway 启停前后，`openclaw.json` 和 SharedPreferences SHA-256 均保持一致。
- 阶段六回归记录：详见 `docs/openclaw-2026.7-regression-record.zh.md`。Stable/Latest、升级/回滚、故障注入和 Base URL 复用前序真实回归证据；独立全新安装网络中断、非空 Goals 内容对比、arm64 真机和旧 WebView 真机仍需外部设备补测。
- 2026-07-31 继续门禁：106 项 Flutter 全量测试通过；`flutter analyze` 无 error/warning、仅保留既有 12 条 info；x86_64 Debug APK 构建成功，大小 `99,059,227` bytes。
- 2026-07-31 安装中断复验：独立空白 x86_64 API 35 AVD 的 Stable 安装已执行到 OpenClaw 包约 95.8%，重启后正确识别为 `upgradeInterrupted` 并进入环境恢复页；恢复页保留重新检测、终端和备份入口，未提供一键删除。该证据不等同于真实网络断开或完整全新安装通过。
- 2026-07-31 Latest 网关复验：原始中文主模拟器上的 `2026.7.1-2` 约 40 秒进入运行中，18789 IPv4/IPv6 loopback 监听正常；停止后无 PRoot/OpenClaw 进程或 LISTEN socket 残留。
- 2026-07-31 完成度审计补强：新增 v3/v4 Node Invoke fixture、未来协议字段容错、迁移数组保序、敏感字段新增/删除脱敏和 doctor 边界测试。升级事务清单改为先于 package 移动落盘，持久化 `packageInstalled / doctorChecked / configMerged / verified` 阶段；启动时检测并回滚任意非终态事务，回滚失败则固定进入人工恢复，不退回首次安装。
- 2026-07-31 覆盖安装复验：最终 Debug APK 使用 `adb install -r` 覆盖原始中文主模拟器后仍进入 Dashboard，OpenClaw 保持 `2026.7.1-2`、Gateway 保持停止；`openclaw.json` 与 SharedPreferences 覆盖前后 SHA-256 一致。
- 阶段七代码质量与文档：完成。协议、恢复、迁移和版本策略保持独立模块；README 已增加通道兼容矩阵、Node.js `24.18.1`、协议协商和恢复模式说明；CHANGELOG 追加未发布兼容升级记录，未改写历史发布条目。
- 当前剩余外部门禁：在允许清空数据的测试窗口或外部可丢弃设备执行 Stable/Latest 完整全新安装与真实网络中断；使用非空 Goals 样本验证内容一致性；在 arm64 真机完成安装、Gateway、Control UI、Pair、Node 冒烟，并单独记录旧 WebView 限制。当前机器按要求仅运行原始中文主 AVD，不清空其现有用户数据。
