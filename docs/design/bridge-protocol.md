# MobileCodex Bridge 协议

## 目标

Bridge 在 Windows 上连接当前 Codex Desktop，并通过认证 WSS 向 Android 客户端提供有限的任务能力。协议不暴露任意 JavaScript、IPC channel、shell、文件路径或通用 tool call。

协议 envelope 的 JSON Schema 位于 mobile-codex-bridge-v1.schema.json，消息示例位于 mobile-codex-bridge-v1.examples.json。

## 分层

| 层 | 职责 |
|---|---|
| Android client | 项目/聊天、任务、审批、结果和重连 UI |
| WSS Bridge | 配对、认证、capability、请求记录、事件恢复 |
| Desktop adapter | 当前 backend、thread/turn、NativePipe 和版本检查 |
| Codex Desktop | 原 Agent 工具、文件、命令和权限执行 |

手机 API 只包含产品范围内已注册的方法。内部 adapter 需要的 NativePipe/IPC 方法不会原样透传。

## Envelope

~~~json
{
  "v": 1,
  "id": "req_turn_1",
  "kind": "request",
  "method": "bridge.turn.start",
  "backendId": "backend_desktop_01",
  "backendGeneration": 3,
  "threadId": "thread_1",
  "payload": {
    "text": "运行测试并修复失败项",
    "mode": "default"
  }
}
~~~

顶层字段必须符合 schema。backend-scoped 请求必须带 backendId 和 backendGeneration；thread/turn 字段冲突时拒绝请求，不改写原参数。

## 能力范围

首版注册的方法包括：

~~~text
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
~~~

实际可用能力由运行时 registry 和 Desktop 版本决定。未注册的方法返回明确错误。

## 请求和恢复

- 请求 id 在同一设备、backend 和 generation 内必须保持参数一致。
- backend 重启或连接替换时递增 generation；旧请求拒绝，不自动转发。
- event 使用 streamId 和递增 seq；客户端按 streamId、seq 去重。
- 缓存缺失时返回 snapshot.required；Bridge 不伪造 cursor。
- 副作用结果为 unknown 时，客户端先使用 bridge.request.get 或业务状态查询，不盲目重发。

## 人工请求

command/file/permission approval、用户问题和支持的 MCP 表单保留原生 request id、参数和 result 语义。Bridge 协调电脑和手机只能提交一次；已处理、过期、旧 generation 或无权限的回复会被拒绝。手机不能自动批准不支持的请求类型。

## 附件和权限

附件只能使用任务回答明确登记的 task-scoped 引用，不能提交任意本机路径。手机不能覆盖 cwd、roots、sandbox、approval、provider 或账号配置。credentials、证书私钥、项目路径和设备 token 不进入日志或手机界面。

## 版本兼容

Desktop 私有组件和运行时可能变化。adapter 先检查 adapters/main/compatibility.json，不匹配时拒绝注入并返回诊断信息。发现某个函数或 schema 不代表它已成为稳定手机能力。

## 相关文档

- 开发计划：app-plan.md
- 手机能力范围：mobile-capability-scope.md
- 验证记录：docs/development/verification.md
