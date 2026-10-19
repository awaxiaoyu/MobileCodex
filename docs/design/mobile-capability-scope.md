# 手机能力范围

## 产品边界

手机是任务入口和结果查看器。Windows Bridge 保留电脑上的 Agent 执行路径，手机只拿到完成任务所需的有限能力。

## 首版保留

| 能力 | 手机行为 |
|---|---|
| 配对和设备管理 | 一次性 pairing、TLS pinning、连接、重连和撤销 |
| 项目与聊天 | 列表、读取、新建、恢复和当前项目选择 |
| 任务控制 | 发送、流式回答、Plan/Default、model/effort、Steer、Interrupt |
| 人工交互 | 用户问题、command/file/permission 审批和支持的 MCP 表单 |
| 结果 | 任务状态、diff、明确关联的附件和必要错误 |
| 恢复 | 有界事件缓存、snapshot、请求状态查询和 generation 检查 |

## 明确排除

下列能力不通过手机 API 暴露：

- Terminal、PTY、stdin、process 管理和任意 shell；
- 通用文件树、任意路径读写、编辑器和 watcher；
- branch、stage、rebase、commit、push 和 Worktree 管理；
- provider、API key、账号、roots、environment、sandbox 和 approval 配置；
- 任意 NativePipe、IPC、JavaScript、动态 tool call 或自动审批；
- Browser/CDP、Computer Use 输入、Desktop 窗口/布局和远程桌面；
- MCP server 安装、OAuth、插件/技能管理和官方 relay；
- iOS 客户端及其他未验证的平台实现。

这些排除项不会关闭 Codex Desktop 自身的能力。用户仍可以通过手机聊天请求 Agent 运行测试、编辑文件或生成结果，电脑会按原有权限和流程执行。

## 协议落实

1. capability registry 只返回已实现且已验证的手机方法。
2. 原生方法和字段使用 allowlist，未知方法拒绝。
3. 手机只提交 projectId、threadId 和业务参数；电脑解析工作区与权限。
4. 文件结果使用 task-scoped artifact 引用，不接受任意本机路径。
5. 副作用结果未知时先查询状态，不盲目重发。
6. 新能力必须有独立的用户场景、权限边界、恢复策略和测试。

## 相关文档

- [开发计划](app-plan.md)
- [Bridge 协议](bridge-protocol.md)
- [协议 schema](mobile-codex-bridge-v1.schema.json)
- [Android UI 设计](ui-design.md)
