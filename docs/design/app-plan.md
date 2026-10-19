# MobileCodex 开发计划

## 项目定位

MobileCodex 由两部分组成：

1. Windows Bridge：连接正在运行的 Codex Desktop，负责配对、权限、版本兼容、请求关联和事件恢复。
2. Android Flutter 客户端：展示项目/聊天、任务状态、回答、审批、diff 和任务附件。

iOS 不属于当前公开源码和 CI 范围。公开仓库不承诺 iOS 构建或兼容性。

## MVP 范围

- 设备配对、连接状态、撤销和重连；
- 已有项目和聊天列表、读取、新建和恢复；
- 发送任务、流式回答、Default/Plan、model/effort；
- Steer、Interrupt、用户问题和支持的审批表单；
- 任务 diff、task-scoped 附件和必要失败诊断；
- 有界事件缓存、snapshot 和请求状态查询。

手机不提供任意 shell、Terminal、通用文件系统、账号配置、原始 IPC、任意 tool call、Worktree 管理或 Desktop 窗口控制。电脑上的 Agent 仍按原有权限执行命令、文件和工具操作。

详细边界见手机能力范围，协议见 Bridge 协议。

## 架构

~~~mermaid
flowchart LR
    Android[Android Flutter client] <-->|authenticated WSS| Bridge[Windows Bridge]
    Bridge --> Adapter[Desktop adapters]
    Adapter --> Desktop[Codex Desktop]
    Desktop --> Agent[Agent tools and workspace]
~~~

Bridge 只向手机注册有限业务方法。手机选择 projectId、threadId 和支持的 model/effort；电脑解析项目环境、权限和工作区，不接受手机覆盖 sandbox、approval 或任意路径。

## 目录约定

~~~text
src/                    Bridge、WSS、RPC、设备和策略
adapters/               Desktop Main/Renderer adapter
native/                 NativePipe 相关代码
schemas/codex/          原生请求和回复 schema
apps/android/           Flutter Android client
scripts/                启动、构建、smoke test 和 benchmark
tests/                  Node fixture 与 Bridge tests
docs/design/            产品范围、协议和 UI 设计
docs/development/       验证、benchmark 和 roadmap
docs/guides/            Desktop 设置入口和运行指南
~~~

## 阶段

| 阶段 | 目标 | 验证 |
|---|---|---|
| P0 | 当前 Desktop 同一聊天的发送、流式回答和一个人工请求 | shared backend、原请求关联和停用恢复 |
| P1 | 配对/WSS、设备撤销、capability registry、generation | 未配对拒绝、旧 generation 拒绝、allowlist 生效 |
| P2 | Android 任务 UI、审批/问题、diff/附件和重连 | 从发送到结果的完整任务链路 |
| P3 | 搜索、改名、归档、置顶、通知和 Automation | 每项能力有独立使用场景与恢复策略 |

## 开发原则

- 先复用当前 Desktop connection，再增加定向 adapter。
- 不因为内部 API 存在就把它公开给手机。
- 副作用请求未知时先查询状态，不自动重发。
- 日志只记录关联 metadata；不记录 token、证书私钥、真实任务内容或本机路径。
- Bridge 协议变化必须同步更新 schema、示例、客户端和测试。

## 相关文档

- 产品和开发范围：手机能力范围
- Bridge 协议：bridge-protocol.md
- UI 设计：ui-design.md
- 验证记录：docs/development/verification.md
