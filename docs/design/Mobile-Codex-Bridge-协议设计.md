# Mobile Codex Bridge 协议与实现设计

实施状态更新（2026-10-15）：协议已经用于持续 Frida shared adapter 和 Flutter 客户端；实际支持与限制见 [README](../../README.md) 和 [验证记录](../p0-verification.md)。后文的未实现说明保留原设计时点。

⚡ [Design]: Bridge 复用已有任务 API，并为必要的 Desktop 业务动作增加定向 adapters。手机协议只提供任务操作、必要交互和结果，不直接暴露全部内部 API。

范围版本 0.2；2026-10-14。具体排除项以 [手机功能范围](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/Mobile-Codex-手机功能范围.md) 为准。本设计、Schema 和示例尚不是可运行 Bridge。

## 1. 范围与分层

| 层 | 职责 | 手机可见 |
|---|---|---|
| 当前 Desktop connection / app-server adapter | 同一 thread/turn 请求、事件和原请求关联 | 聊天、发送/Steer/Interrupt、必要结果 |
| NativePipe / Electron IPC adapter | 在正确身份与窗口/host 上下文调用已注册业务动作 | 已有项目、聊天管理、后续 Automation 等选中动作 |
| 定向进程内 adapter | 外部入口不足时，在实际拥有状态的进程内包装原业务方法 | 同一稳定 Bridge 业务接口 |
| 原 Agent 执行路径 | shell、文件、subagent、MCP、生成/编译、Browser/Computer Use 等 | 摘要、结果、必要人工交互 |
| Bridge 连接层 | 配对、权限、registry、请求记录、事件恢复 | 连接状态和错误 |

主机内部入口不自动成为手机能力。仅为保留范围开发 adapters；Hooks 仅在缺少必要事件时补充。Terminal、通用文件系统、Worktree/Git 管理器、配置管理、窗口布局、实时 Voice 与远程桌面本轮暂缓。

“获取未暴露 API”可以是调用已有私有接口，也可以是在进程内包装业务方法后新增本机接口；不要求原应用已有 HTTP endpoint。加载、来源授权、NativePipe peer authorization、WindowsApps 打包/签名条件需 PoC，函数名存在不能证明外部可调用。

## 2. Backend 与承载

`bridge.backends.list` 返回 `backendId`、`kind`、`generation`、版本及连接状态：

- `backendId` 是实例身份，例如 `backend_desktop_01`。
- `kind` 为 `desktop-shared` 或 `companion-standalone`。只有已验证接入当前 Desktop 原连接才能标记 shared。
- backend 重启或原连接被替换时递增 `generation`；请求中的 `backendGeneration` 必须匹配。旧请求拒绝，不自动转发新连接。
- 相同历史 `threadId` 不证明属于同一 live session。

手机通过认证后的 WSS `/rpc/v1` 连接，每个 WebSocket text frame 承载一个 envelope。电脑内部 adapter 使用当前用户 ACL 保护的本机 IPC。app-server stdio 保持原 JSONL 格式，不混入 Bridge 字段。

结果文件/图片等通过单独认证的 artifact 通道传输，RPC 返回 task-scoped 引用。它只提供已登记且授权的任务产物，不接收任意本机路径；具体资源签发、格式及下载实现随 MVP 补齐。实时音视频通道本轮暂缓。

## 3. Envelope：mobile-codex-bridge/v1

```json
{
  "v": 1,
  "id": "req_turn_1",
  "kind": "request",
  "method": "codex.request",
  "backendId": "backend_desktop_01",
  "backendGeneration": 3,
  "threadId": "thread_1",
  "ack": {"streamId": "stream_desktop_01_g3", "seq": 1842},
  "payload": {
    "method": "turn/start",
    "params": {
      "threadId": "thread_1",
      "input": [{"type": "text", "text": "运行测试并修复失败项"}]
    }
  }
}
```

| 字段 | 规则 |
|---|---|
| v | 协议主版本，不兼容变更递增 |
| id | request/response 关联键；server.request/server.response 也使用同一 id，由 Bridge 映射原生 id |
| kind | request、response、event、server.request、server.response、snapshot、error |
| method | 必须是注册业务方法或允许的原生交互类型，禁止任意 eval/IPC |
| backendId/backendGeneration | backend-scoped 消息必须同时携带；全局 capabilities/backends 请求可省略 |
| threadId/turnId | 根据动作绑定；顶层和原生 params 都存在时必须一致，冲突拒绝而不改写 params |
| streamId/seq | event/snapshot 的流身份和位置，generation 换代后建立新流 |
| ack | 可选连续接收位置 {streamId, seq}，不是动作完成状态 |
| payload | 按 method/kind 校验；原生字段保留该版本 schema 的合法结构 |

自有可选字段无值时省略；原生 params/result 的省略、null、扩展字段按原 schema 处理。顶层 envelope 拒绝未定义字段，不能将这一规则盲套到原生 schema。

成功 response 使用相同 id/method，payload 是结果；`codex.request` 成功时 payload 保留原生 result。失败使用 kind:error、相同 id/method 和 `{code, message, retryable, data?}`。无法关联的连接级错误可省略 id。

请求 id 在同设备/backend/generation 内不能对应不同参数。请求记录不是 exactly-once 保证；副作用结果未知时查询业务状态，不能盲重发。

## 4. 能力目录与业务方法

手机主界面使用以下自有方法，是否可调用由 registry 决定：

```text
bridge.capabilities.get
bridge.backends.list
bridge.project.list
bridge.thread.list
bridge.thread.read
bridge.thread.create
bridge.thread.resume
bridge.turn.start
bridge.turn.steer
bridge.turn.interrupt
bridge.model.list
bridge.diff.read
bridge.artifact.list
bridge.events.resume
bridge.snapshot.get
bridge.request.get
```

这些是设计方法，不是本机已有的 Codex 方法。thread.create 使用已有 projectId；主机从项目解析 cwd/environment/roots，继承原权限，不接受任意手机路径或 permission override。具体业务参数 schema 随 adapter 实现补齐。

后续小批次注册聊天 search/fork/rename/archive/pin、queue/Goal、Local Automation/Heartbeat；不默认注册 file.read/write、terminal.start/input/stop、worktree.create/archive、preview/window focus 或 config.write。

Capability 示例：

```json
{
  "protocol": "mobile-codex-bridge/v1",
  "scopeVersion": "0.2.0",
  "bridgeVersion": "0.1.0",
  "backendId": "backend_desktop_01",
  "backendGeneration": 3,
  "capabilities": [
    {
      "name": "bridge.turn.start",
      "sourceAdapter": "desktop-connection",
      "status": "verified",
      "stability": "private",
      "requires": ["thread.control"],
      "verifiedBuild": "13901"
    },
    {
      "name": "bridge.automation.list",
      "sourceAdapter": "native-pipe",
      "status": "discovered",
      "stability": "private",
      "requires": ["automation.read"]
    }
  ]
}
```

这是假设 turn adapter 已通过 PoC 的示例，本机尚未完成外部接入。status：discovered、verified、disabled、version_mismatch、account_unavailable、not_implemented；stability：schema、experimental、private、fallback。

discovered 不可作为手机可执行按钮；verified 也只表示对应版本、动作及上下文通过实测。目录只展示保留范围的已注册能力，不复制 schema 或 NativePipe 的全部 tools/list。

## 5. 原生 API 的有限透传

Bridge 内部可以复用完整本机 schema；手机 `codex.request` 只通过显式方法和字段 allowlist。首版候选：

```text
model/list
turn/start
turn/steer
turn/interrupt
```

thread/list/read/start/resume 等优先由业务 adapter 内部调用，向手机提供任务 view model，避免把整套 backend 管理和内部 items 作为手机接口。

校验顺序：

1. 当前 backend/schema 支持方法，且 Bridge registry 允许。
2. 设备拥有对应 thread/project 权限；generation、host/thread/turn 一致。
3. 原生 schema 合法，并通过该方法的字段策略。仅有 schema 合法还不够。
4. turn/start 继承所选 thread/project 的 cwd、environment、roots 与 permissions；手机不能提交覆盖 sandbox、approval、provider/config、任意动态工具等字段。model/effort/Plan 按支持列表和原设置机制处理。

排除 command/exec、thread/shellCommand、process/*、通用 fs/*、config/*、任意 tool/call、NativePipe tools/call 原样透传。用户仍可通过正常聊天请求 Agent 运行命令或编辑文件，按原 Codex policy 执行。

initialize/initialized 属于 Bridge 管理。独立连接按原协议握手一次；当前 Desktop 连接已经初始化时复用其生命周期，不重复 initialize。mock/experimentalMethod 不入产品。experimentalApi 和实际 feature/account 可用性分别验证。

## 6. 双向人工请求

所有原生 ServerRequest 都必须有正确处理归属；只把需要手机用户决定的请求映射成 server.request。

| 类型 | 路由 |
|---|---|
| command/file/permissions approval | 手机保留完整原 params 和对应 decision 语义 |
| item/tool/requestUserInput | 手机问题卡片；结果按原 answers schema |
| MCP elicitation | 支持的表单/授权提示可在手机处理；无法处理时保留 Desktop 路径 |
| dynamic tool execution | 原主机处理器执行；手机不负责模拟工具 |
| auth token refresh / attestation / 自动审批 | 原主机路径；需要人工到电脑操作时只提示待处理 |

```json
{
  "v": 1,
  "kind": "server.request",
  "id": "srvreq_9",
  "method": "item/commandExecution/requestApproval",
  "backendId": "backend_desktop_01",
  "backendGeneration": 3,
  "threadId": "thread_1",
  "turnId": "turn_2",
  "payload": {
    "threadId": "thread_1",
    "turnId": "turn_2",
    "itemId": "item_3",
    "command": "npm test",
    "cwd": "C:\\work\\demo"
  }
}
```

payload 仅展示关键字段，正式传输保留本机 schema 定义的完整 params。这是审批详情，不是文件系统/终端管理接口。

```json
{
  "v": 1,
  "kind": "server.response",
  "id": "srvreq_9",
  "method": "item/commandExecution/requestApproval",
  "backendId": "backend_desktop_01",
  "backendGeneration": 3,
  "payload": {"decision": "accept"}
}
```

Bridge 维护手机 id → backend generation + 原生 request id 映射，保留原生 integer/string 类型。不同请求按各自 result schema 校验；不能统一“批准/拒绝”结构。Bridge 与 Desktop 原处理路径协调一次有效提交，多设备并发或 Desktop 已处理时返回 resolved/conflict 状态，不能再次回应上游。

已解决、过期、旧 generation、无权限回复拒绝；未知结果不重发审批。手机不支持的类型保留电脑路径，不能默认批准。Full Access 与已有授权按原 Codex policy 执行，不增加每步重复确认。

## 7. 必要事件与恢复

手机事件范围：

- 回答和 plan delta、thread/turn 状态、必要工具活动摘要；
- 任务 diff、结果附件、可读失败诊断；
- 待处理人工请求及 resolved；
- 已注册用户业务的状态，例如后续 automation 更新。

stdout/stderr 逐字流、PTY/terminal interaction、fs/changed、全部 hook/subagent/debug/reasoning 流不做独立转发接口。主机可以消费底层事件以生成摘要和诊断，不能因裁剪丢失任务错误。内部数据与用户可见事件流分开。

```json
{
  "v": 1,
  "kind": "event",
  "method": "event.item.delta",
  "backendId": "backend_desktop_01",
  "backendGeneration": 3,
  "threadId": "thread_1",
  "turnId": "turn_2",
  "streamId": "stream_desktop_01_g3",
  "seq": 1843,
  "payload": {
    "source": "app-server",
    "codexMethod": "item/agentMessage/delta",
    "data": {"delta": "测试已通过"}
  }
}
```

每个授权事件流有 streamId 和递增 seq；设备只确认自己完整订阅的流。scope/订阅范围变化或 backend 换代时建立新 stream，避免越权重放或漏事件。

bridge.events.resume 接收 `{streamId, afterSeq}`。可重放时先回复 `{status:"replaying", streamId, throughSeq}`，再按序发缺失与实时事件；手机按 (streamId, seq) 去重。缓存缺失返回 snapshot.required。

bridge.snapshot.get 返回 kind:snapshot，其 streamId/seq 是 snapshot 已包含的位置；状态读取与 cursor 必须有一致性边界。无法一致恢复的 adapter 如实返回重新同步状态，不能伪造 cursor。

Bridge 默认在内存中有界保存必要完整事件，metadata 不能重放文本 delta。持久化内容缓存需明确配置期限和清理；审计日志默认只存版本、device/backend/thread/turn/id、adapter、错误码和耗时。

bridge.request.get 用 `{requestId}` 查询同设备/backend/generation 的 pending/completed/failed/unknown 记录。unknown mutation 先读业务状态，不能自动重发创建任务、写文件或 Git 操作。

## 8. 私有能力研究范围

优先序：

1. 用本机 schema 和 Desktop 原 connection 复用任务流程；
2. 通过已授权 NativePipe tools/list 定位需要的 Desktop 业务；
3. 使用已有 electronBridge、IPC/worker/shared object 入口；
4. 入口不足时定向包装拥有状态的业务方法；
5. 缺必要事件时才考虑 Hooks。

例如后续 bridge.automation.create：校验参数 → 选择已验证 NativePipe tool 或进程内 automation handler → 调用原流程 → 回传结果及状态。手机不需要知道底层 IPC channel，也不能自行挑选任意工具。

不为暂缓项做接口发现、hook、兼容层或手机页面。每个选中 adapter 记录 capability、请求/回复类型、事件映射、版本/加载/恢复与实测结果。没有原需求的全量 hook/内存扫描不属于首版。

## 9. 实现门槛与交付

P0：当前 Desktop 同一聊天发送/流式输出/审批/Interrupt，加一个保留范围的 Desktop 只读动作（例如现有 automation 查询）。独立 app-server 成功不替代 shared 接入。

P1–P2：配对、有限 registry/WSS、手机任务 UI、diff/附件、generation、重连和 mutation 对账。P3 按使用场景加入聊天管理/队列/Goal/Automation。

核心验证：真实同会话任务、一次人工往返、断线与旧 generation、排除接口和字段无法透传、一项 Desktop 业务、一个授权产物、未知版本/停用恢复。不为原工具实现镜像测试。

当前设计产物：

- [Bridge envelope JSON Schema](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/mobile-codex-bridge-v1.schema.json)：约束 envelope、透传外壳及恢复/查询；业务参数和原生内容由部署 registry/Codex schema 再校验。
- [协议消息示例](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/mobile-codex-bridge-v1.examples.json)
- [147 条范围 JSON](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/mobile-codex-feature-scope.json)
- [开发计划](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/Mobile-Codex-App-开发计划.md)

未来实现交付：Windows Bridge、手机任务客户端、有限 capability registry、选中 adapters 与版本/恢复实测记录。终端、文件系统等暂缓模块不作为交付要求。

本地已确认入口：ASAR preload 的 electronBridge、Main mcp-request 与 NativePipe handlers、codex-app-tools/server.mjs。当前 Desktop 外部连接、进程内加载与手机全链路尚未实测。
