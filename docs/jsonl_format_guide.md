# OpenClaw Session JSONL 文件格式说明

> 文档生成时间：2026-04-09 02:10  
> 基于会话：`b7300bff-a214-4c11-97ae-eab26883c67a`

---

## 📋 什么是 JSONL？

**JSONL (JSON Lines)** = 每一行都是一个独立的 JSON 对象

- ✅ 易于流式读取
- ✅ 每行可独立解析
- ✅ 适合日志和对话记录

---

## 🗂️ 文件位置

```
~/.openclaw/agents/main/sessions/<session-id>.jsonl
```

**当前最新会话:**
```
/Users/susu/.openclaw/agents/main/sessions/b7300bff-a214-4c11-97ae-eab26883c67a.jsonl
```

---

## 📊 记录类型总览

| 类型 | 说明 | 出现位置 |
|------|------|----------|
| `session` | 会话元信息 | 第 1 行 |
| `model_change` | 模型配置变更 | 开头 |
| `thinking_level_change` | 思考级别设置 | 开头 |
| `custom/model-snapshot` | 模型快照 | 开头 |
| `message` | 对话消息 | 主体内容 |

---

## 1️⃣ Session 头信息

**第 1 行 - 会话基本信息**

```json
{
  "type": "session",
  "version": 3,
  "id": "b7300bff-a214-4c11-97ae-eab26883c67a",
  "timestamp": "2026-04-08T01:03:43.107Z",
  "cwd": "/Users/susu/.openclaw/workspace"
}
```

| 字段 | 说明 |
|------|------|
| `type` | 固定为 `"session"` |
| `version` | 会话格式版本号 |
| `id` | 会话唯一 ID (UUID) |
| `timestamp` | 会话创建时间 (ISO 8601) |
| `cwd` | 工作目录 |

---

## 2️⃣ 模型配置变更

**第 2 行 - 使用的模型**

```json
{
  "type": "model_change",
  "id": "7f59d586",
  "parentId": null,
  "timestamp": "2026-04-08T01:03:43.116Z",
  "provider": "custom-api-siliconflow-cn",
  "modelId": "Qwen/Qwen3.5-397B-A17B"
}
```

| 字段 | 说明 |
|------|------|
| `provider` | 模型服务商 |
| `modelId` | 具体模型 ID |

---

## 3️⃣ 思考级别设置

**第 3 行 - 推理开关**

```json
{
  "type": "thinking_level_change",
  "id": "9b229e99",
  "parentId": "7f59d586",
  "timestamp": "2026-04-08T01:03:43.116Z",
  "thinkingLevel": "off"
}
```

**可选值:** `on` / `off`

---

## 4️⃣ 模型快照

**第 4 行 - 模型配置快照**

```json
{
  "type": "custom",
  "customType": "model-snapshot",
  "data": {
    "timestamp": 1775610223119,
    "provider": "custom-api-siliconflow-cn",
    "modelApi": "openai-completions",
    "modelId": "Qwen/Qwen3.5-397B-A17B"
  },
  "id": "34632c2e",
  "parentId": "9b229e99",
  "timestamp": "2026-04-08T01:03:43.119Z"
}
```

---

## 5️⃣ 用户消息

```json
{
  "type": "message",
  "id": "cefcc998",
  "parentId": "34632c2e",
  "timestamp": "2026-04-08T01:03:43.126Z",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "text",
        "text": "嗯嗯"
      }
    ],
    "timestamp": 1775610223122
  }
}
```

---

## 6️⃣ 助手回复 (纯文本)

```json
{
  "type": "message",
  "id": "215b81b1",
  "parentId": "cefcc998",
  "timestamp": "2026-04-08T01:03:47.322Z",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "thinking",
        "thinking": "用户只是简单回应，没有具体问题或任务...",
        "thinkingSignature": "reasoning_content"
      },
      {
        "type": "text",
        "text": "\n\n早呀，主人！☀️\n\n新的一天开始啦～今天有什么安排吗？"
      }
    ],
    "api": "openai-completions",
    "provider": "custom-api-siliconflow-cn",
    "model": "Qwen/Qwen3.5-397B-A17B",
    "usage": {
      "input": 22192,
      "output": 109,
      "cacheRead": 0,
      "cacheWrite": 0,
      "totalTokens": 22301,
      "cost": {
        "input": 0,
        "output": 0,
        "cacheRead": 0,
        "cacheWrite": 0,
        "total": 0
      }
    },
    "stopReason": "stop",
    "timestamp": 1775610223124
  }
}
```

**关键字段说明:**

| 字段 | 说明 |
|------|------|
| `content[].type` | 内容类型 (`thinking`/`text`/`toolCall`) |
| `content[].thinking` | 思考过程内容 |
| `content[].text` | 实际回复文本 |
| `usage.input` | 输入 token 数 |
| `usage.output` | 输出 token 数 |
| `usage.totalTokens` | 总 token 数 |
| `usage.cost.total` | 总费用 |
| `stopReason` | 停止原因 (`stop`/`toolUse`/`length`) |

---

## 7️⃣ 助手回复 (包含工具调用)

```json
{
  "type": "message",
  "id": "8804dc5d",
  "parentId": "32c583dc",
  "timestamp": "2026-04-08T06:43:49.970Z",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "thinking",
        "thinking": "主人发来了一个 cpolar 服务日志文件...",
        "thinkingSignature": "reasoning_content"
      },
      {
        "type": "text",
        "text": ""
      },
      {
        "type": "toolCall",
        "id": "019d6bd533f188de8690d4d5b0b3918d",
        "name": "read",
        "arguments": {
          "path": "/Users/susu/.openclaw/media/inbound/cpolar_service.log---14ddcd24-763f-457a-9bb1-fd3804267cf7"
        }
      }
    ],
    "api": "openai-completions",
    "provider": "custom-api-siliconflow-cn",
    "model": "Qwen/Qwen3.5-397B-A17B",
    "usage": {
      "input": 22839,
      "output": 213,
      "totalTokens": 23052,
      "cost": {"total": 0}
    },
    "stopReason": "toolUse",
    "timestamp": 1775630622352
  }
}
```

**工具调用字段:**

| 字段 | 说明 |
|------|------|
| `type` | 固定为 `"toolCall"` |
| `id` | 工具调用唯一 ID |
| `name` | 工具名称 (如 `read`, `exec`, `web_search`) |
| `arguments` | 工具参数 (键值对) |

---

## 📁 完整文件结构

```
第 1 行  ──┐
第 2 行  ──├─ 会话头信息 (只出现一次)
第 3 行  ──┤
第 4 行  ──┘
           │
第 5 行  ──┐
第 6 行  ──┤
第 7 行  ──├─ 第 1 轮对话
第 8 行  ──┤
           │
第 9 行  ──┐
第 10 行 ──┤
第 11 行 ──├─ 第 2 轮对话
第 12 行 ──┤
           │
   ...     │
           │
           └─ 后续对话交替进行...
```

---

## 🔑 核心字段速查表

| 字段 | 出现位置 | 说明 |
|------|----------|------|
| `type` | 所有记录 | 记录类型标识 |
| `id` | 所有记录 | 记录唯一 ID (UUID) |
| `parentId` | 除第 1 行外 | 父记录 ID (形成对话树) |
| `timestamp` | 所有记录 | ISO 8601 时间戳 |
| `message.role` | `type=message` | `user` 或 `assistant` |
| `message.content[]` | `type=message` | 内容数组 |
| `content[].type` | content 数组内 | `thinking` / `text` / `toolCall` |
| `usage.totalTokens` | assistant 消息 | 本次对话 token 消耗 |
| `stopReason` | assistant 消息 | 停止原因 |

---

## 💡 实用解析命令

### 统计行数
```bash
wc -l ~/.openclaw/agents/main/sessions/<session-id>.jsonl
```

### 查看文件大小
```bash
ls -lh ~/.openclaw/agents/main/sessions/<session-id>.jsonl
```

### 提取所有用户消息
```bash
grep '"role":"user"' ~/.openclaw/agents/main/sessions/<session-id>.jsonl | jq '.message.content[0].text'
```

### 提取所有助手回复
```bash
grep '"role":"assistant"' ~/.openclaw/agents/main/sessions/<session-id>.jsonl | jq '.message.content[] | select(.type=="text") | .text'
```

### 统计 token 用量
```bash
grep '"totalTokens"' ~/.openclaw/agents/main/sessions/<session-id>.jsonl | jq '.usage.totalTokens' | paste -sd+ | bc
```

---

## 🔍 示例：解析单条消息

使用 `jq` 工具解析:

```bash
# 读取第 6 行 (第一条助手消息)
sed -n '6p' session.jsonl | jq '.'
```

输出:
```json
{
  "type": "message",
  "id": "215b81b1",
  "timestamp": "2026-04-08T01:03:47.322Z",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "thinking",
        "thinking": "用户只是简单回应..."
      },
      {
        "type": "text",
        "text": "早呀，主人！☀️"
      }
    ],
    "usage": {
      "totalTokens": 22301
    }
  }
}
```

---

## 📝 注意事项

1. **每行都是独立 JSON** - 可以用 `cat file.jsonl | while read line; do echo "$line" | jq '.'; done` 逐行解析
2. **时间戳格式** - 使用 ISO 8601 (UTC 时间)
3. **parentID 关系** - 形成对话树结构，可以追溯对话历史
4. **token 统计** - `usage` 字段包含详细的 token 使用信息
5. **工具调用** - `stopReason: "toolUse"` 表示助手调用了工具

---

## 🛠️ 相关工具

| 工具 | 用途 |
|------|------|
| `jq` | JSON 解析和过滤 |
| `sed` | 提取特定行 |
| `grep` | 搜索特定类型记录 |
| `wc` | 统计行数 |
| `node` / `python` | 编写脚本批量处理 |

---

_文档由 雅雅 🦎 生成于 2026-04-09_