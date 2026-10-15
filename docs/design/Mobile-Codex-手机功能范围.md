# Mobile Codex 手机功能范围裁剪

⚡ [Design]: 手机作为任务遥控器和结果入口。Bridge 只接入用户需要主动操作或查看的能力，主机保留原 Agent 执行；不把 Codex 的全部工具、桌面控件和内部维护转换成手机 API。

依据：2026-10-14 的本机功能盘点，27 类、147 个条目。以下是产品范围决定，不能理解为功能不存在或技术上不可桥接。原盘点中的代码/schema 证据等级不变，外部接入仍需 PoC。

## 1. 分类结果

| 类别 | 条目数 | 处理 |
|---|---:|---|
| 手机保留 | 11 | 用户主动操作有价值；按 MVP / 后续小批次开发 |
| 拆分保留 | 42 | 只接用户可见的一小部分，其他部分不桥接 |
| 主机内部 | 32 | 继续由 Codex/电脑执行，无独立手机 API |
| 暂缓桥接 | 62 | 本轮不研究其私有接入、不开发 adapter 或手机页面 |

合计 147 个原始条目，其中 94 个整条暂不开发手机业务接口；另有 42 个条目需要裁剪。这是条目计数，不能换算为精确 API 数量或功能覆盖百分比。

## 2. 暂不桥接的能力

| 能力组 | 原条目 | 本轮决定 |
|---|---|---|
| Terminal / Shell / Process | 06.01–06.05 | 不开发远程 Terminal、PTY、stdin/resize/kill、shell 配置或后台进程管理。Agent 仍可执行命令，手机接收任务摘要与必要审批。 |
| 文件系统 / IDE | 07.01–07.05 | 不开发文件树、通用文件读写/目录操作、编辑器、go-to-definition、IDE 打开、watcher 转发。保留任务 diff 和明确产物附件。 |
| Git / Worktree 运维 | 08.01、08.03–08.06、10.01–10.04 | 不开发 branch/checkout/stage/rebase/commit/push、worktree 生命周期/Handoff 的专用控制面。保留必要分支状态、diff、PR 结果；操作意图可通过聊天发送。 |
| 环境 / 登录 / 账户配置 | 04.04、11.02–11.04、12.02、24.03–24.05、26.05 | 不从手机安装 WSL、配置 roots/env/secrets、登录主机账号、设置 provider 或编辑原始 config。继承已配置主机。 |
| Agent 内部调度 | 05.01、05.05、16.02、16.06–16.07 | 不桥接 subagent 调度、tool discovery、Code Mode/Node REPL、动态工具加载等手机操作接口。必要 NativePipe discovery 只留在 adapter 内部。 |
| 生成 / 搜索 / 编译的工具 API | 19.01、19.05–19.06、20.02–20.03、21.01 | 不单独暴露文档生成、dependency 安装、compiler transport、Web Search 工具调用。用任务请求和结果返回覆盖用户流程。 |
| 自动状态管理 | 01.07、07.05、10.03、23.01、26.04 | 不为压缩/迁移、watch、ownership、prune、自动 hooks、缓存清理开发手机按钮。Hooks adapter 只在缺少必要事件时按需增加。 |
| 插件 / MCP / 技能管理 | 15.01–15.06、16.01、16.04–16.05、23.02–23.04 | 暂缓安装/卸载、marketplace、MCP server 配置、OAuth 管理、hooks/instructions 编辑、导入同步。保留已启用能力引用与必要用户交互。 |
| Browser / Computer Use 控制面 | 17.01–17.06、18.01–18.05 | 不做远程 browser tab/CDP、鼠标键盘、cookie/password/profile、Office add-in 或 Messages 管理。Agent 继续使用已有工具；手机仅看结果并回应审批。 |
| Desktop 窗口 / 系统 / Mini | 25.01、25.03、25.05–25.07 | 不桥接多窗口、tab/layout/focus、主题字体、快捷键、Windows 关联、Mini/Pets、外设设置；手机自己实现 UI。 |
| 高级编辑 / 实时媒体 | 19.03–19.04、20.01、21.03–21.04、22.01–22.05 | 暂缓 Spreadsheet/LaTeX/Canvas 完整编辑器、实时 Voice、桌面 Dictation/Appshot 与屏幕上下文。保留附件预览和文字反馈。 |
| 重复远程基础设施 / Cloud | 12.01–12.04、13.01–13.08 | 不接官方 Remote pairing/relay、SSH/daemon/exec-server 控制面，不新建专门 Cloud adapter。自建 Bridge 保留自己的配对与连接。 |
| 维护与条件 surface | 23.05–23.06、26.01–26.03、27.01–27.07 | 暂缓远程更新、官方诊断反馈、Memory/Chronicle、ChatGPT Work/Pages/Sites/Teams/Meetings/Micro；废弃/mock API 永不进入手机目录。 |

## 3. 几个必须保留的边界

- **命令审批 ≠ Terminal。** 不开发交互终端，仍需把任务要求的 command/file/permission 审批及原始信息交给手机，按原规则回复。
- **任务 diff / 产物附件 ≠ 通用文件系统。** 保留当前任务的变更和明确生成的文件；不提供任意路径读取、目录遍历或文件编辑。附件引用应绑定任务及授权，不靠在手机调用通用 fs API 获取。
- **结果预览 ≠ 操控 Desktop panel。** 优先在手机渲染图片/PDF或下载已授权产物，不为控制桌面预览窗口开发 RPC。
- **让 Agent 执行 ≠ 手机直接调用工具。** 用户仍可说“运行测试”“提交这次修改”“生成 PDF”。电脑按原流程选择工具；Bridge 只传任务、必要交互和结果。原 Agent 的能力及已有 Full Access 授权保持。
- **内部 adapter ≠ 手机功能。** 版本检测、backend 身份、请求关联、NativePipe 授权/发现、断线恢复仍是 Bridge 必需机制，不因此给手机开放完整工具目录。
- **不用终端/文件 UI ≠ 过滤审批详情。** 不截断原请求中决定批准所需的命令、路径、范围或风险说明。更底层的 stdout/watch/debug 流无需单独同步到手机。

## 4. 收缩后的开发范围

MVP 只做：设备配对/连接、已有项目和聊天列表、发送任务、流式回答与简要进度、Steer/Interrupt、审批/用户问题、结果附件、任务 diff，以及重连恢复。model/effort/Plan 使用已有后端支持的选择范围。

第二批做：聊天搜索/Fork/改名/归档/置顶、队列/Goal、Local Automation/Heartbeat、完成与待审批通知。手机不镜像 Desktop 窗口或配置页。

暂缓：所有上表中的专用控制面及私有 adapters。P0 只验证当前 Desktop 同一聊天，再选一个保留范围内的 Desktop 专有能力（例如查询现有 automation）。无需先桥接终端、文件系统、worktree 或 compiler。

## 5. Bridge 协议如何落实范围

1. 默认只注册保留业务方法；不扫描 schema 后自动公开所有 API。
2. 原生 `codex.request` 使用显式 allowlist。其存在不提供 command/exec、process/*、通用 fs/*、config/*、任意 tool/call 或私有 IPC 的绕行入口。
3. `tools/list` 的内部发现结果仅用于选择 adapter；`bridge.capabilities.get` 只返回实际已注册的手机能力，不复制全部 tool catalog。
4. 回答、必要任务状态、diff/附件和待处理人工请求进手机事件流。stdout/stderr、文件 watcher、全部 subagent/Hook/debug 消息不做独立通道；执行失败通过任务错误和必要诊断摘要可追溯。
5. 自动审批、dynamic tool execution、内部 attestation 等由原主机处理路径接手。手机只响应自己有权限且可处理的人工交互；无法处理的流程保留电脑路径。
6. 新接入能力只在有明确手机使用场景后加入，不以“本机存在 API”为开发理由。

## 6. 147 条逐项取舍

“手机保留”不表示这轮已实现；“主机内部”也不表示关闭原功能。主机动作可继续由聊天请求和 Agent 执行路径触发。

### 01 聊天与历史

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 01.01 新建与恢复 | 拆分保留 | 新建、恢复现有聊天 | Temporary Chat 条件流程、CLI 参数镜像 |
| 01.02 Fork 与继续 | 手机保留 | Fork、继续任务 | CLI fork/resume 的独立控制台界面 |
| 01.03 历史管理 | 拆分保留 | 聊天列表、读取、归档/反归档 | 删除首版暂缓；unsubscribe、turn/item 分页由 Bridge 管理 |
| 01.04 侧栏管理 | 拆分保留 | 改名、置顶、已读状态 | 操控 Desktop sidebar、分组布局、手工排序、自定义 section |
| 01.05 搜索 | 拆分保留 | 聊天搜索 | 桌面查找控件与焦点；手机自行渲染命中 |
| 01.06 分享与复制 | 拆分保留 | 手机复制消息、分享结果引用 | 电脑 clipboard、conversation path、工作目录复制、共享 snapshot 专有流程 |
| 01.07 上下文管理 | 拆分保留 | 必要 context/用量提示 | 手动压缩、inject_items、底层 revert、rollout 迁移和压缩；电脑按原逻辑处理 |

### 02 消息输入与响应展示

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 02.01 输入类型 | 拆分保留 | 文字、手机照片或附件输入 | 电脑文件夹拖放、localAudio、本机路径选择器；实时音频首版暂缓 |
| 02.02 上下文引用 | 拆分保留 | 已启用 skill/App 的简单引用 | 文件树选取、桌面 browser tab picker、文件夹上下文选择器 |
| 02.03 流式输出 | 拆分保留 | 回答增量、计划、简要进度、diff | 逐字 stdout/stderr、底层 reasoning/debug 流、实时音频流 |
| 02.04 富内容 | 拆分保留 | Markdown、代码块、图片、结果附件、可读图表 | 同步 Desktop renderer、任意 MCP Apps surface、Canvas/复杂交互组件 |
| 02.05 结构化输出 | 主机内部 | — | outputSchema、CLI JSON 格式由电脑处理；不另做手机配置 API |

### 03 回合控制、队列与 Goal

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 03.01 回合控制 | 手机保留 | 发送、Steer、Interrupt | — |
| 03.02 消息队列 | 手机保留 | 任务队列与 follow-up 管理（MVP 后） | CLI queue 参数镜像 |
| 03.03 回合与线程设置 | 拆分保留 | model、effort、Plan 等用户设置；继承当前项目权限 | 手机修改 cwd、roots、environment、sandbox/permission 配置 |
| 03.04 持续 Goal | 手机保留 | Goal 查看、编辑、暂停/恢复（MVP 后） | 底层状态推进由 Codex 负责 |
| 03.05 Token budget | 暂缓桥接 | — | tokenBudget 编辑和完整预算仪表盘；用量提示保留在其他条目 |

### 04 模型与执行模式

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 04.01 模型选择 | 手机保留 | 可用模型选择 | provider 配置与模型加载由电脑负责 |
| 04.02 Reasoning effort 与速度 | 手机保留 | 支持的 effort/速度选择 | 底层 service tier 协商与 provider 适配 |
| 04.03 Default / Plan | 手机保留 | Default / Plan 切换 | — |
| 04.04 Provider 与本地模型 | 暂缓桥接 | — | provider、API key、Ollama/LM Studio 安装与连接配置 |
| 04.05 输出偏好 | 拆分保留 | 手机本地显示偏好；继承电脑 instructions | 从手机编辑 AGENTS.md、全局 web search/provider/config、桌面 style 设置 |

### 05 Multi-agent 与跨聊天协调

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 05.01 Subagent 执行与活动 | 拆分保留 | 可选 subagent 活动摘要 | spawn/message/wait 等内部调度；不让手机手动指挥每个 subagent |
| 05.02 跨聊天创建与读取 | 拆分保留 | 复用普通聊天的创建、读取、Fork | 另做跨聊天 coordinator 面板、wait_threads 控制 API |
| 05.03 跨聊天操作 | 拆分保留 | 普通聊天管理与 follow-up | 远程操作 Desktop 导航/焦点；Agent 跨聊天消息路由 |
| 05.04 执行地点 Handoff | 暂缓桥接 | — | checkout/worktree/host Handoff 专用按钮与迁移管理 |
| 05.05 旧字段兼容 | 主机内部 | — | deprecated multiAgentMode；不开发兼容 API |

### 06 Shell、Terminal 与 Process

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 06.01 命令执行 | 主机内部 | — | 直接 shell/unified_exec/PTY、逐字输出；保留原 Agent 执行和必要审批 |
| 06.02 交互进程 | 主机内部 | — | stdin、process spawn/kill、resize；由原 Agent/主机处理 |
| 06.03 后台 Terminal | 主机内部 | — | 后台 Terminal 列表、清理、终止；任务停止用 turn interrupt |
| 06.04 集成 Terminal | 暂缓桥接 | — | 集成 Terminal 面板、terminal tab、shell 选择、远程终端 |
| 06.05 Shell 环境 | 主机内部 | — | cwd、环境继承、shell snapshot、多 roots、worktree shell 环境 |

### 07 文件系统与代码编辑

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 07.01 文件管理 API | 主机内部 | — | 通用文件读写、目录、metadata、删除、复制、watch API；结果附件另有受限通道 |
| 07.02 文件导航与搜索 | 暂缓桥接 | — | 文件树、fuzzy search、文件内搜索、go to line |
| 07.03 内置代码编辑 | 暂缓桥接 | — | 源码编辑器、跳转定义、编辑 tab、文件导航、blame |
| 07.04 外部打开 | 暂缓桥接 | — | 远程打开电脑 IDE、默认打开目标、OS 文件关联 |
| 07.05 文件监视 | 主机内部 | — | fs watcher、编辑器刷新、preview source；需要结果时由电脑产出 |

### 08 Git 工作流

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 08.01 仓库与分支 | 拆分保留 | 所选项目的分支名称等必要状态 | init、checkout、分支搜索/创建、origin/upstream 设置与 Git 管理器 |
| 08.02 Diff 与 Changes | 拆分保留 | 任务 diff、变更摘要 | 完整 Changes panel、基线切换、blame、多 source Git 浏览器 |
| 08.03 Stage 与回退 | 暂缓桥接 | — | stage/unstage/revert 专用 RPC；可在聊天明确要求 Codex 按原权限执行 |
| 08.04 Commit / Push | 暂缓桥接 | — | Commit/Push 专用 workflow；可在聊天明确要求 Codex 执行 |
| 08.05 PR 创建与合并 | 拆分保留 | 结果中的 PR 链接及简要状态 | PR 创建/merge 按钮与 GitHub 管理界面；请求可走聊天 |
| 08.06 Rebase | 暂缓桥接 | — | Rebase 专用接口；保留电脑原能力 |

### 09 Code Review 与 PR 管理

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 09.01 本地 Review | 拆分保留 | 通过聊天发起 review、查看 findings | 独立 Review 控制台、CLI review UI |
| 09.02 PR 浏览 | 拆分保留 | 当前任务关联 PR 摘要/链接 | PR 搜索、stack/inbox、全仓 revision 浏览和完整 PR 客户端 |
| 09.03 CI 与合并状态 | 拆分保留 | 当前任务 CI 通过/失败及必要诊断 | 全量 checks/mergeability/updates 管理器 |
| 09.04 Review 执行 | 拆分保留 | 通过聊天要求 review、查看与反馈 findings | startReview/chatReview 等全部插件 RPC 的独立透传 |
| 09.05 PR 写操作 | 暂缓桥接 | — | PR 更新、评论、submitReview、resolve、merge 专用接口；请求走聊天 |
| 09.06 监控与修复 | 暂缓桥接 | — | Watch-and-fix/auto-merge 专有配置页；可经聊天创建已授权任务 |

### 10 Managed Git Worktree

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 10.01 创建与附加 | 主机内部 | — | managed worktree 创建/attach/ref/取消进度；继承电脑原工作流 |
| 10.02 归档与恢复 | 暂缓桥接 | — | worktree archive/restore 管理界面与独立 RPC |
| 10.03 生命周期 | 主机内部 | — | ownership、topology、fetch、prune、恢复元数据 |
| 10.04 任务搬移 | 暂缓桥接 | — | 任务 checkout/worktree/host 搬移界面与 RPC |

### 11 项目、Local Environment 与 WSL

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 11.01 项目管理 | 拆分保留 | 列出、选择电脑已有项目；必要的聊天项目归属 | 新建/导入/删除项目、open folder、多 roots、目录管理 |
| 11.02 执行 Environment | 拆分保留 | 只读执行地点/不可用状态 | environment/add、runtime roots 与执行环境配置 |
| 11.03 Local Environment 配置 | 暂缓桥接 | — | Local Environment 设置、setup 脚本、快捷 environment actions |
| 11.04 Windows Native / WSL | 暂缓桥接 | — | WSL 安装、连接配置与 native/WSL 切换管理；继承电脑已有环境 |

### 12 Cloud 执行

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 12.01 Cloud Tasks | 暂缓桥接 | — | 专门 Cloud task 创建/apply/diff 和执行地点切换；现有聊天只返回可读状态 |
| 12.02 Cloud Environment | 暂缓桥接 | — | Cloud Environment、secret、网络策略、共享/editor 管理 |
| 12.03 Cloud 预览 | 暂缓桥接 | — | Cloud live browser overlay、文件预览专用控制 |
| 12.04 Cloud Automations | 暂缓桥接 | — | Cloud automation 独立接入；先接电脑已有 Local/Heartbeat |

### 13 Remote 与设备通信

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 13.01 Remote Control 管理 | 暂缓桥接 | — | Codex 官方 Remote Control enable/disable/status；自建 Bridge 连接不依赖它 |
| 13.02 设备配对 | 暂缓桥接 | — | 官方 Remote pairing/client revoke API；自有设备配对另行实现 |
| 13.03 手机控制 UI | 暂缓桥接 | — | 镜像官方手机控制设置页；自建 App 使用自己的设备界面 |
| 13.04 SSH | 暂缓桥接 | — | SSH 编辑、登录、daemon bootstrap、多远端 host 管理；首版只连指定电脑 |
| 13.05 协议传输 | 主机内部 | — | Codex transport 选择留在电脑；手机只用自有 WSS 协议 |
| 13.06 Daemon | 主机内部 | — | Codex daemon bootstrap/update/stop 等管理；不是手机业务 API |
| 13.07 独立 exec-server | 暂缓桥接 | — | 独立 exec-server、environment forward、Noise/AWS token 注册 |
| 13.08 Device identity 与锁屏控制 | 暂缓桥接 | — | 官方 device identity/TPM/锁屏控制移植；不自动绕过解锁条件 |

### 14 Automation 与 Heartbeat

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 14.01 Local scheduled tasks | 手机保留 | Local automation 查看、创建、修改、暂停/删除（MVP 后） | 调度执行器留在电脑 |
| 14.02 Thread Heartbeat | 手机保留 | Heartbeat 设置、暂停/恢复、下一次运行与结果（MVP 后） | 定时唤醒和归档执行由电脑负责 |
| 14.03 Schedule | 手机保留 | 手机 schedule 表单（MVP 后） | 不镜像 Desktop 控件；RRULE 在主机 adapter 内转换 |
| 14.04 运行配置 | 拆分保留 | prompt、现有项目、model/effort、历史与运行状态 | Cloud 地点配置、执行环境和底层调度参数 |
| 14.05 通知偏好 | 手机保留 | 通知开关、失败才通知、更新状态 | Desktop notification sound 由电脑处理 |

### 15 Skills、Plugins 与 Marketplace

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 15.01 Skills | 拆分保留 | 已启用 skill 简单列表/mention | 安装依赖、extraRoots、reload、trust、技能文件编辑与管理器 |
| 15.02 Plugins | 暂缓桥接 | — | plugin 安装/卸载/搜索/reconcile/管理员设置；已启用插件照常供 Agent 使用 |
| 15.03 Marketplace | 暂缓桥接 | — | marketplace add/remove/upgrade/list 管理页 |
| 15.04 Plugin Sharing | 暂缓桥接 | — | plugin share/save/checkout/updateTargets/delete |
| 15.05 远程与默认插件 | 主机内部 | — | remote/bundled plugins 的获取、cache 与更新 |
| 15.06 模板技能 | 暂缓桥接 | — | 模板库创建/删除/编辑；现有模板可继续由聊天调用 |

### 16 MCP、Apps 与 Dynamic Tools

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 16.01 MCP Server 接入 | 暂缓桥接 | — | MCP server command/env/header 配置、连接管理、reload |
| 16.02 MCP Tools 与 Resources | 主机内部 | — | tools/resources discovery/call、底层 event stream；Agent 在主机使用 |
| 16.03 Elicitation | 拆分保留 | 必要的用户问题、可支持的 MCP 表单/授权提示 | 底层工具执行与 token 流程；无法在手机处理的 OAuth 留给电脑 |
| 16.04 Apps / Connectors | 拆分保留 | 已连接 App 的简单引用与连接异常提示 | OAuth/安装/连接器管理；电脑先完成配置 |
| 16.05 MCP Apps UI | 暂缓桥接 | — | 嵌入所有 MCP Apps UI、data 清理、permission 设置页 |
| 16.06 工具编排 | 主机内部 | — | deferred loading、tool search、Code Mode、Node REPL、functions.exec 内部编排 |
| 16.07 Desktop MCP 桥接 | 主机内部 | — | NativePipe 身份、metadata、工具发现与 dispatch；仅是 Bridge 内部 adapter，不对手机开放全部 tools |

### 17 内置与外部 Browser

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 17.01 内置 Browser | 暂缓桥接 | — | 远程操控 Desktop browser tab、地址栏、zoom、print；结果 URL 可在手机本地打开 |
| 17.02 Agent Browser Use | 主机内部 | — | Agent DOM/CDP/浏览器操作；仅传必要任务摘要/结果截图 |
| 17.03 网页标注与设计 | 暂缓桥接 | — | Desktop annotation/design overlay 控制；普通图片反馈可走聊天 |
| 17.04 浏览器数据 | 暂缓桥接 | — | 电脑 browser history/cookie/password/cache/download 设置与管理 |
| 17.05 External Browser | 主机内部 | — | Agent 控制外部 Chrome/Edge 的会话与扩展连接；不给手机原始浏览器控制 API |
| 17.06 Profile 与 Extensions | 暂缓桥接 | — | browser profile import、extension manager |

### 18 Computer Use 与应用集成

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 18.01 Native App 控制 | 主机内部 | — | Agent Native App 控制/截图/输入；保留原可用性限制和审批 |
| 18.02 应用权限 | 拆分保留 | 任务所需应用权限请求 | Always-allowed apps 设置页、capability 配置 |
| 18.03 Office Live | 主机内部 | — | Office add-in 连接和 Agent 交互；手机查看产物/结果即可 |
| 18.04 Messages 集成 | 主机内部 | — | Messages 工具及 read/send 授权执行；不重建手机 Messages 管理 UI |
| 18.05 锁屏使用 | 暂缓桥接 | — | 锁屏 Computer Use 配置、远程解锁与相关 gates |

### 19 文档、表格、幻灯片与预览

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 19.01 Office / PDF 生成 | 主机内部 | — | DOCX/XLSX/PPTX/PDF 生成、编辑、渲染；产物通过结果通道返回 |
| 19.02 文件预览 | 拆分保留 | 结果附件的手机预览/下载 | 控制 Desktop preview panel、Notebook/编辑器与窗口位置 |
| 19.03 文档反馈 | 拆分保留 | 对结果发文字/图片修改建议 | Desktop redline/annotation/feedback surface 镜像与精确坐标编辑 |
| 19.04 表格 UI | 暂缓桥接 | — | 手机 Spreadsheet cell/formula/format editor |
| 19.05 Workspace Dependencies | 主机内部 | — | bundled Node/Python/deps 发现、安装/reset、诊断路径 |
| 19.06 文件类型处理器 | 主机内部 | — | plugin 文件类型 dispatch、Windows 文件关联 |

### 20 LaTeX

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 20.01 源码与 PDF | 拆分保留 | 最终 PDF 与编译失败摘要 | .tex source editor、Desktop 自动预览、插图/布局操作 |
| 20.02 Compile Diagnostics | 主机内部 | — | compile_latex_document 与完整诊断链由 Agent/电脑执行 |
| 20.03 独立运行环境 | 主机内部 | — | 专用 app-server/sandbox/compiler transport |

### 21 搜索、图像与媒体

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 21.01 Web Search | 主机内部 | — | web search 执行和策略；搜索结果沿回答返回 |
| 21.02 Image View / Generation | 拆分保留 | 生成/查看结果图片、发修改建议 | local image 工具执行、imagegen 调度与 Desktop preview controller |
| 21.03 Visualization | 拆分保留 | 手机可渲染的 Mermaid/图表结果 | Desktop 可视化编辑器、所有交互 surface/分享控制镜像 |
| 21.04 音视频显示 | 拆分保留 | 结果媒体引用及手机可播放的内容 | 电脑播放器控制、完整 Desktop 媒体传输；实时流首版暂缓 |

### 22 Voice、Dictation 与 Appshot

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 22.01 实时 Voice | 暂缓桥接 | — | 实时 Voice session、SDP/WebRTC、audio delta、voice 选择；首版文字/附件 |
| 22.02 Voice 控件 | 暂缓桥接 | — | 控制电脑 microphone/output、全局 hotkeys、voice 设置 |
| 22.03 Dictation | 暂缓桥接 | — | 电脑 Dictation/录音历史/设备设置；手机可用本机键盘语音输入，无需 Bridge |
| 22.04 Appshot / Screen Selection | 暂缓桥接 | — | 电脑 Appshot、区域截图、destination/sound/Mini 设置；手机照片独立输入 |
| 22.05 Voice 屏幕上下文 | 主机内部 | — | voice-only screen context 按原约束执行；首版不额外订阅 |

### 23 Hooks、导入与个性化

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 23.01 生命周期 Hooks | 主机内部 | — | lifecycle Hooks 执行；仅缺必要任务事件时才加 adapter，不逐项桥接全部 hooks |
| 23.02 Hook 管理 | 暂缓桥接 | — | hook trust/review/reload/global/project 配置页 |
| 23.03 外部 Agent 导入 | 暂缓桥接 | — | 外部 Agent detect/import/sync/history/progress 管理 |
| 23.04 自定义 Instructions | 暂缓桥接 | — | AGENTS.md/override/instructions 编辑与同步；直接继承电脑配置 |
| 23.05 Codex Memory | 暂缓桥接 | — | Memory reset/mode/settings；本机 memories flag=false |
| 23.06 Computer History / Chronicle | 暂缓桥接 | — | Chronicle 活动记录与过滤管理；本机 chronicle flag=false |

### 24 权限、Sandbox 与账号

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 24.01 权限边界 | 拆分保留 | 显示当前有效权限和任务所需的额外权限请求 | 手机改 sandbox/profile/roots/network 等全局配置 |
| 24.02 人工与自动审批 | 拆分保留 | 人工审批、问题与必要 MCP elicitation 原始语义 | auto_review/guardian 内部判定和调度；不让手机重做 |
| 24.03 Windows Sandbox | 主机内部 | — | Windows Sandbox setup/readiness/service；仅异常时给可读任务错误 |
| 24.04 Authentication | 暂缓桥接 | — | 电脑登录/logout/refresh、API key/provider/gateway/Bedrock 设置；沿用主机登录 |
| 24.05 User Verification | 暂缓桥接 | — | User Verification enroll/attestation 移植；需要时提示到电脑完成 |
| 24.06 Usage 与 Limits | 拆分保留 | 当前 usage/rate limit 提示 | credits 购买、billing/analytics/reset credit、完整账号管理 |

### 25 Desktop UI、Windows 集成与 Mini

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 25.01 窗口与布局 | 暂缓桥接 | — | Desktop 多窗口/popout/tab/layout/zoom/快捷命令菜单 |
| 25.02 导航与活动 | 拆分保留 | 手机任务列表、未读与需要注意状态 | Desktop sidebar 焦点、pinned summary、recent 快捷键与活动布局 |
| 25.03 Appearance | 暂缓桥接 | — | Desktop appearance/theme/font/translucency import/export；手机主题本地处理 |
| 25.04 通知与声音 | 拆分保留 | 任务完成、审批、问题的手机通知 | 电脑 sound/foreground 偏好/系统 badge 控制 |
| 25.05 Mini / Pets | 暂缓桥接 | — | Mini/Pets/avatar/PiP/custom pet、关联 voice/dictation 窗口 |
| 25.06 Windows 系统集成 | 暂缓桥接 | — | Windows 文件关联、右键菜单、Copilot key、开机启动等系统设置；installer 管理自身启动 |
| 25.07 设置与语言 | 拆分保留 | 手机本地语言、send/follow-up 偏好 | Desktop hotkeys、shell/default file target/projectless folder 等设置 |

### 26 维护、诊断与数据

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 26.01 App / CLI 更新 | 暂缓桥接 | — | 远程升级 Desktop/CLI/Store；Bridge 仅检测版本并提示兼容 |
| 26.02 诊断与性能 | 主机内部 | — | doctor/trace/debug/task manager/logs；Bridge 只返回自身错误码和连接状态 |
| 26.03 Feedback | 暂缓桥接 | — | 官方 feedback/upload 与诊断附件；手机 App 自身反馈无需 Codex adapter |
| 26.04 Storage 与 Cleanup | 拆分保留 | 聊天归档/反归档复用已有接口 | rollout/subagent 清理、worktree prune、压缩/迁移和缓存管理 |
| 26.05 配置管理 | 暂缓桥接 | — | 通用 config/read/write/batchWrite、features/profile 编辑；按已批准的小型业务方法设置 |

### 27 共享代码与条件功能

| ID / 功能 | 决策 | 手机保留 | 本轮不桥接或留在电脑 |
|---|---|---|---|
| 27.01 ChatGPT Chat / Work | 暂缓桥接 | — | 镜像 ChatGPT Chat/Work 页面、account/profile 与共享项目流程 |
| 27.02 Pages / Canvas | 暂缓桥接 | — | Pages/Canvas 全编辑器及图形工具 |
| 27.03 Sites / Appgen | 暂缓桥接 | — | Sites/Appgen 发布、数据库、访问与自动化控制面 |
| 27.04 Dots / Teams | 暂缓桥接 | — | Dots/Teams、join/create/workspace/team plugins |
| 27.05 Meetings | 暂缓桥接 | — | Meetings 录音/笔记流程的独立桥接 |
| 27.06 Codex Micro | 暂缓桥接 | — | Codex Micro 外设 key/stick/knob/mic/light mappings 与 games |
| 27.07 Debug / 实验遗留 | 主机内部 | — | debug/removed/deprecated/mock API、GPU/confetti 实验；不纳入产品 |

## 7. 相关文件

- [开发计划](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/Mobile-Codex-App-开发计划.md)
- [Bridge 协议设计](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/Mobile-Codex-Bridge-协议设计.md)
- [范围 JSON](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/mobile-codex-feature-scope.json)
- [原始本机功能盘点](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/Codex本机功能清单.md)

本轮只完成分析和范围设计，未安装、注入或修改 Codex，也未实现可运行 Bridge。
