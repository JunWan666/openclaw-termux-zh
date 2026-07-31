# OpenClaw 2026.7.x 兼容性分析报告

## 1. 报告目的

本报告用于评估 `openclaw-termux-zh` 在保留 OpenClaw `2026.3.23` 稳定体验的前提下，兼容 OpenClaw `2026.7.x` 所需的改造范围、兼容边界、主要风险和验证证据。

本阶段只进行分析，不修改协议、安装、恢复或配置业务逻辑。

## 2. 分析基线

### 2.1 当前项目状态

- 当前分支：`main`
- 当前提交：`d1940de91534ae14295ac2c52142d24eb706d942`
- 工作区已有未提交修改：20 个文件，主要涉及安装 UI、停止安装、npm 安装参数、Node.js `24.18.1` 和 Android PRoot 运行时修复。本次升级必须保留这些现有改动，不得覆盖。
- Flutter 单元测试基线：50 项全部通过。
- Flutter analyze 基线：无 error/warning；有 12 条既有 info 级弃用或字符串提示。
- 当前推荐 OpenClaw：`2026.3.23`。
- 当前 Node.js：arm64/x86_64 使用 `24.18.1`，armv7 使用 `22.22.2`。

### 2.2 对比版本与官方证据

- OpenClaw `2026.3.23` 源码标签：`v2026.3.23`，提交 `ccfeecb6887cd97937e33a71877ad512741e82b2`。
- OpenClaw `2026.7.1` 源码标签：`v2026.7.1`，提交 `2d2ddc43d0dcf71f31283d780f9fe9ff4cc04fe4`。
- npm 最新目标：`2026.7.1-2`。
- `2026.3.23` Node 要求：`>=22.16.0`。
- `2026.7.1-2` Node 要求：`>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0`。
- Node.js `24.18.1` 同时满足稳定版和最新版要求。

官方参考：

- [OpenClaw 2026.7.1 Release](https://github.com/openclaw/openclaw/releases/tag/v2026.7.1)
- [Gateway Protocol](https://github.com/openclaw/openclaw/blob/v2026.7.1/docs/gateway/protocol.md)
- [Gateway protocol version constants](https://github.com/openclaw/openclaw/blob/v2026.7.1/packages/gateway-protocol/src/version.ts)
- [OpenClaw Android GatewayProtocol](https://github.com/openclaw/openclaw/blob/v2026.7.1/apps/android/app/src/main/java/ai/openclaw/app/gateway/GatewayProtocol.kt)
- [OpenClaw Doctor](https://github.com/openclaw/openclaw/blob/v2026.7.1/docs/cli/doctor.md)

## 3. 总体结论

项目不需要推倒重写，也不需要重做现有安装 UI 和用户流程。兼容工作属于中等规模、分阶段的兼容层增强。

可以继续复用的部分：

- Ubuntu RootFS、Node.js 解压和 PRoot 启动方式。
- `npm install -g`、指定版本安装、升级和回滚主体流程。
- `openclaw gateway --verbose` 启动方式。
- OpenClaw 自带 Control UI 的 WebView 展示方式。
- `/root/.openclaw` 用户数据目录和现有备份能力。
- 现有 Dashboard、Gateway、配置编辑和版本选择 UI。

必须优先改造的部分：

1. Gateway 协议层必须从“写死 v3”改成可扩展的协议协商层。
2. 环境检测必须区分“完整”“可修复”“需要用户处理”“首次安装”，不能把可修复状态直接送回首次安装。
3. 升级前后必须保护配置、Token、Pair、Sessions、Goals 和 Provider 数据，并采用有备份、可验证、可回滚的迁移策略。
4. 自定义 Base URL 不得继续被迁移函数自动追加 `/v1`。
5. Stable 与 Experimental 必须成为显式版本通道，而不是只依赖“最新/推荐”两个标签。

## 4. Gateway Protocol v3 与 v4 差异

### 4.1 官方协议版本边界

OpenClaw `2026.3.23`：

```text
PROTOCOL_VERSION = 3
```

OpenClaw `2026.7.1`：

```text
PROTOCOL_VERSION = 4
MIN_CLIENT_PROTOCOL_VERSION = 4
MIN_NODE_PROTOCOL_VERSION = 3
MIN_PROBE_PROTOCOL_VERSION = 3
```

含义：

- 普通控制客户端必须使用协议 v4。
- 经过认证的 Node 客户端目前仍允许协议 v3。
- 轻量探针目前仍允许协议 v3。
- 当前项目以 `role=node` 连接，短期内可依靠服务端兼容继续连接 2026.7.x，但不能获得 v4 新能力，也无法保证未来继续兼容。

### 4.2 当前项目实现

当前 `NodeService` 在 connect 中写死：

```text
minProtocol = 3
maxProtocol = 3
```

当前实现已经具备：

- `connect.challenge` nonce 签名。
- v2 设备签名载荷。
- 基础 token/deviceToken 保存。
- `caps`、`commands`、`permissions` connect 字段。
- `node.invoke.request` 与 `node.invoke.result`。
- 基础 WebSocket 重连退避。

### 4.3 当前实现相对官方 2026.3.23 客户端的缺口

项目当前实现不仅缺少 v4，也比 OpenClaw 官方 `2026.3.23` Android 客户端的协议处理更简化：

- 未解析 `error.details.code`。
- 未解析 `canRetryWithDeviceToken`。
- 未解析 `recommendedNextStep`。
- 未实现共享 Token 失败后仅一次的 deviceToken 重试预算。
- 未根据明确的鉴权失败暂停自动重连。
- 未保存设备 Token 对应的 role/scopes。
- 未解析 `sessionDefaults.mainSessionKey`。
- 未区分可重试错误与确定性错误。

因此不能只把常量从 3 改成 4；否则虽然握手版本数字变化，错误恢复和鉴权行为仍不符合新版协议。

### 4.4 v4 新增或强化的处理要求

| 领域 | v4/2026.7.x 要求 | 当前状态 | 风险 |
| --- | --- | --- | --- |
| 协议协商 | 客户端声明安全支持的 min/max，读取协商后的 protocol | 写死 3/3，不保存协商结果 | 高 |
| Auth | token、deviceToken、bootstrap/password 来源分离，结构化恢复建议 | 只在 gateway token 和 device token 间简单选择 | 高 |
| Scope | hello-ok 返回协商后的 role/scopes，Token 与 scopes 绑定 | 不保存 scopes | 高 |
| Retry | 启动 sidecars 时返回 `retryAfterMs`，应在连接预算内重试 | 统一使用本地指数退避 | 中高 |
| Capability | connect 时声明 caps/commands/permissions，服务端按声明授权 | 已声明，但未校验服务端 features/policy | 中 |
| Session | hello-ok 可返回 `sessionDefaults.mainSessionKey`，v4 增加订阅能力 | 未保存 session 默认值 | 中 |
| Error | 结构化 code/details/reason/recommendedNextStep | 只读取顶层 code/message | 高 |
| Policy | hello-ok 的 payload/buffer/tick 策略应被客户端遵守 | 未解析 | 中 |
| Future compatibility | 未知字段应保留/忽略，协议范围应集中配置 | 协议逻辑分散在 Service/Frame/WS | 高 |

### 4.5 推荐的兼容设计

- 新增独立协议层，集中维护：
  - 客户端支持范围。
  - 服务端协商结果。
  - Auth 来源和重试状态。
  - hello-ok、policy、features、sessionDefaults。
  - 结构化错误和重试建议。
- 对 `2026.3.23`：首选发送兼容范围 `3..4`；如果旧服务端严格拒绝范围跨越，则按明确的 protocol mismatch 结果降级重连 `3..3`，而不是盲目循环。
- 对 `2026.7.x`：优先协商 v4；Node 服务端仍接受 v3 时保留降级能力。
- 只有确认服务器返回协议不匹配时才改变协议范围；鉴权错误不得触发协议降级。
- 未知新增字段必须安全忽略，同时保留原始 Map 供日志和未来扩展使用。

## 5. 安装、升级与运行时差异

### 5.1 Node.js

Node.js `24.18.1` 是当前合适的固定版本：

- 满足稳定版 `2026.3.23`。
- 满足 `2026.7.1-2`。
- 避免不受支持的 Node 23。
- 比动态跟随 Node 最新大版本更可控。

现有 Node 约束解析只提取版本表达式中的第一个版本号，不能正确理解 `||`、`<23`、`<25` 等范围。当前固定 Node 24.18.1 恰好安全，但版本校验实现仍存在潜在误判，例如 Node 23 会被错误判定为满足最新版要求。

### 5.2 OpenClaw 安装

现有安装流程按具体版本下载 tarball，并执行 `npm install -g`，完成后创建 bin wrapper 和执行 `openclaw --version`。主体兼容，不需要重写。

需要增强：

- 安装前生成保护性状态快照。
- 安装完成后验证实际版本等于目标版本。
- 安装失败时保留旧 package、配置和用户数据，避免出现“旧版已删除、新版未完成”的窗口。
- 最终版本切换应采用 staging/commit 思路，或至少保留可回滚包和旧版本元数据。
- Node engines 应使用完整 semver 判断。

## 6. 升级恢复差异与 Issue #45

### 6.1 当前完整性判断

当前 `isBootstrapComplete()` 要求以下项目全部存在：

- RootFS。
- `/bin/bash`。
- Node.js。
- OpenClaw `package.json`。
- `/usr/local/bin/openclaw`。
- `bionic-bypass.js`。

该判断能防止把 npm 半安装误判为完成，但不能区分“可修复”与“必须重新安装”。只要 wrapper 或 bypass 丢失，即使 RootFS、配置和用户数据全部完好，App 仍会进入首次安装向导。

Issue：[#45 升级中断，无法识别旧容器](https://github.com/JunWan666/openclaw-termux-zh/issues/45)

### 6.2 应有的状态模型

建议检测结果至少包含：

- `fresh`：没有有效 RootFS 和用户数据，可以首次安装。
- `complete`：所有运行条件满足且 `openclaw --version` 成功。
- `repairable`：RootFS、Node、package.json 或用户数据存在，但 wrapper/bypass/目录等可重建项缺失。
- `upgradeInterrupted`：package.json、npm staging/cache、旧版本元数据呈现升级中断特征。
- `manualRecoveryRequired`：用户数据存在，但 Node/OpenClaw 核心损坏且自动修复不足以保证安全。
- `runningExistingGateway`：即使静态标记不完整，只要检测到现有 Gateway 进程，也不得进入首次安装或删除环境。

### 6.3 修复动作边界

允许自动执行：

- 创建缺失运行目录。
- 重建 OpenClaw wrapper/symlink。
- 重建 Bionic Bypass 和 Node wrapper。
- 重写 DNS bind 目标。
- 执行 `openclaw --version` 验证。
- 验证 Gateway 是否可启动或已运行。

禁止自动执行：

- 删除 RootFS。
- 删除 `/root/.openclaw`。
- 删除 `openclaw.json`、`.env`、agents、sessions、memory、skills、extensions。
- 因 wrapper 缺失而自动运行 npm 重装。
- 因配置验证失败而覆盖整份配置。

## 7. 配置迁移差异

### 7.1 当前项目会直接写入的配置区域

- `gateway.mode`。
- `gateway.reload.mode`。
- `gateway.nodes.allowCommands/denyCommands`。
- `discovery.mdns.mode`。
- `models.providers.*`。
- `agents.defaults.model.primary`。
- `agents.defaults.models` 中的旧 alias 清理。
- `channels.*`。
- `gateway.auth.token` 及若干兼容读取路径。

项目大多数写入使用 Map 合并，原则上不会覆盖无关顶层字段。但部分迁移会主动规范化 Base URL，样例配置应用会覆盖整个 `openclaw.json`，这些路径需要纳入保护。

### 7.2 2026.7.x 官方迁移能力

OpenClaw 2026.7.x 已包含大量官方配置、状态、Session、Cron、Provider 和插件迁移，并提供：

- `openclaw doctor --lint`：只读检查。
- `openclaw doctor --fix --non-interactive`：应用安全的非交互修复。
- 配置写入时自动保留 `.bak` 轮转备份。
- `openclaw doctor --post-upgrade`：升级后兼容探针。

因此 App 不应复制 OpenClaw 内部所有迁移规则。正确策略是：App 负责保护、编排、差异验证和回滚；字段语义迁移优先交给目标版本自带的官方迁移器。

### 7.3 推荐迁移顺序

1. 停止 Gateway，并确认进程结束。
2. 记录旧版本和目标版本。
3. 对 `/root/.openclaw` 受保护数据创建本地升级快照。
4. 对 `openclaw.json`、`.env`、设备 Token、App Preferences 生成独立校验摘要。
5. 安装目标 OpenClaw，但不删除用户目录。
6. 执行 `openclaw --version`。
7. 执行目标版本的只读 `doctor --lint --json`。
8. 仅在有官方安全迁移项时执行 `doctor --fix --non-interactive`。
9. 对迁移前后配置做结构化 diff：已有非空用户值不得被默认值覆盖。
10. 校验 Token、Pair、Sessions、Goals、Providers 等保护项仍存在。
11. 启动 Gateway 并完成健康检查。
12. 失败时回滚配置和 package 版本；用户数据快照始终保留。

### 7.4 数据保护范围

现有 workspace backup 已覆盖：

- `.env`
- `openclaw.json`
- `data`
- `memory`
- `skills`
- `config`
- `extensions`
- `agents`

Goals 属于 Session 状态，应随 Session 存储保留。实施前必须通过 2026.7.x 实际目录清单确认 Sessions/Goals 是否全部落在上述范围；若存在新的 SQLite 或状态目录，应只扩展备份白名单，不改变旧备份格式的读取能力。

## 8. Base URL 与 Issue #43

Issue：[#43 自动补齐 v1 后缀造成 404](https://github.com/JunWan666/openclaw-termux-zh/issues/43)

当前行为：

- `custom-openai` 默认使用 `appendV1IfMissing`。
- `migrateCustomProviderConfigIfNeeded()` 会再次规范化已保存的自定义 Base URL。
- 当前单元测试明确期待 OpenAI-compatible 自定义地址自动追加 `/v1`。

这与新的兼容要求冲突。应调整为：

- 内置 OpenAI 使用已知固定地址 `https://api.openai.com/v1`。
- 内置 OpenRouter 使用已知固定地址 `https://openrouter.ai/api/v1`。
- 其他内置 Provider 由各自元数据决定固定路径。
- 自定义 Provider 保存用户原始输入，仅 trim，不追加、不删除路径。
- 连接测试根据所选 API 协议在请求时拼接 `chat/completions`、`responses` 或 `messages`，但不得反写 Base URL。
- 迁移不得回溯修改用户已经保存的自定义 URL；已有 `/v1` 也应原样保留。

## 9. 版本管理差异

当前版本标签只有：

- npm 最新版本：Latest。
- 内置推荐集合：Recommended。

需要扩展为稳定通道：

- `2026.3.23`：Stable，默认选择，离线时也必须可见。
- npm 最新 `2026.7.x`：Experimental，不默认覆盖 Stable。
- 用户可安装、升级、降级和回滚。
- UI 流程保持现状，只增加标签、风险说明和确认文案。
- 版本元数据应记录目标 Node engines、通道和验证状态。

现有 `compareVersions()` 只是提取数字，能区分 `2026.7.1-2`，但不是完整 semver；版本通道和 engines 判断不能继续依赖该简化逻辑。

## 10. Issues 关联判断

| Issue | 与 2026.7.x 关系 | 当前判断 |
| --- | --- | --- |
| #44 protocol v4 | 直接相关 | Node v3 暂时受服务端兼容，但项目需要正式支持协商和 v4 语义 |
| #45 升级中断进入向导 | 直接影响升级安全 | 必须增加可修复状态和修复模式 |
| #43 Base URL `/v1` | 配置兼容直接相关 | 必须修复，且迁移不得再次改写 URL |
| #35 apt 包不可用 | 安装基础设施 | 当前预构建 RootFS/镜像策略已有缓解，需纳入回归 |
| #33 resolv.conf 缺失 | 升级/安装基础设施 | 当前已有多重 DNS 兜底，需纳入回归 |
| #32 Control UI 4008/黑屏 | 新 UI 可能放大问题 | 主要受旧 Android WebView 能力影响，需记录最低 WebView 要求和错误提示 |

## 11. 测试覆盖缺口

当前 50 项测试没有覆盖：

- NodeFrame/Gateway 协议协商。
- v3/v4 hello-ok。
- Auth 失败与 deviceToken 单次重试。
- `retryAfterMs`。
- Scope/role 保存。
- WebSocket 重连暂停与恢复。
- 安装状态分类与修复模式。
- package.json 存在但 wrapper 缺失。
- Bionic Bypass 重建。
- 升级前后用户数据清单对比。
- 3.23 到 7.x 的真实升级。
- 最新版 Gateway、Pair、Control UI、Node、Sessions、Goals。
- 自定义 URL 完全原样保存。
- 完整 semver engines 判断。

## 12. 风险分级

### 高风险

- 协议数字直接改成 4，导致 3.23 无法连接。
- 升级先删除旧 OpenClaw，再安装失败，留下不可运行环境。
- 将可修复环境误判为首次安装并诱导用户重装。
- 自动迁移覆盖 Token、Provider 或自定义 URL。
- 备份范围遗漏 2026.7.x 新增状态数据库。

### 中风险

- v4 服务端启动期 `retryAfterMs` 未处理，造成错误重连或假失败。
- Node Token 与 scopes 未绑定，权限升级/降级后持续失败。
- Control UI 对旧 WebView 的兼容性下降。
- 简化 semver 对未来 Node engines 产生误判。

### 低风险

- Stable/Experimental 标签和说明文案。
- README 兼容矩阵更新。

## 13. 兼容性判定

| 场景 | 当前状态 | 完成改造后的目标 |
| --- | --- | --- |
| 全新安装 2026.3.23 | 已支持 | 行为不变 |
| 全新安装 2026.7.x | Node 已满足，其他未完整验证 | Experimental 可用且完整测试 |
| 3.23 Gateway/Control UI | 已支持 | 不回退 |
| 7.x Gateway/Control UI | 预计主体可运行，未证明 | 自动化与模拟器实测通过 |
| 3.23 Android Node | v3 | 保持通过 |
| 7.x Android Node | 依赖服务端 Node v3 兼容 | 优先 v4、必要时安全降级 |
| 3.23 → 7.x 原地升级 | 未完整验证 | 数据、配置、Pair、Sessions、Goals 全保留 |
| 7.x → 3.23 回滚 | 可安装旧版本但未验证状态兼容 | 明确风险、保护数据、可恢复 |
| 升级中断恢复 | 不完善 | 自动进入修复模式，不重装 |

## 14. 分析门禁结论

可以进入实施，但必须按以下顺序：

1. 先抽象和测试协议层。
2. 再实现环境分类与修复模式。
3. 再实现受保护的升级迁移编排。
4. 再修复 Base URL。
5. 最后增加版本通道和完整真实场景测试。

每一阶段都必须先增加针对性测试，再修改实现；完成后执行单元测试、静态分析和 x86_64 Debug APK 构建。阶段验证失败时不得进入下一阶段。
