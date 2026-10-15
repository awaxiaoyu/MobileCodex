# Codex 本机功能清单

⚡ [Analysis]: 基于本机安装包、CLI、app-server schema、插件和当前工具目录的功能盘点。

分析日期：2026-10-14。按用户能力归并，覆盖安装文件中能识别的主要功能与全部生成的协议方法；不把共享代码、隐藏入口或 feature flag 当成已实际开放的功能。

## 1. 结论与范围

- 本机 Desktop product version **26.1007.21434**，Windows package version **26.1007.2314.0**，build **13901**，CLI **0.162.0-alpha.17.2**。不同版本号属于不同层。
- 清单归并为 **27 类 / 147 个功能项**。这里的“项”是一组用户能力，不是函数数量。
- app-server 默认生成 **105 ClientRequest**，含 experimental 时为 **170**；其中 `mock/experimentalMethod` 是测试接口，因此不能说有 170 个产品功能。
- 完整协议还有 **11 ServerRequest、84 ServerNotification、1 ClientNotification**。默认 schema 有 10 ServerRequest。客户端必须处理服务端请求与事件，不能只实现请求发送。
- `project/*`、`remoteControl/*`、`thread/realtime/*` 已存在于 experimental schema；应纠正此前因未加 `--experimental` 而认为这些接口不存在的判断。
- 核心 Agent 协议、Desktop IPC、MCP/Plugins、云端服务是不同接口层。没有从本机证据确认一个供第三方手机应用稳定调用“桌面全部功能”的统一协议。
- 本轮只读分析、生成报告；没有启用 Remote Control、改配置、创建模型任务、进行配对、提交 Git/PR 操作或测试云端服务。

### 证据等级

| 标记 | 含义 |
|---|---|
| API / CLI | 本机生成 schema 或 help 存在；不等同所有部署都允许调用 |
| Desktop / worker / 插件 | 本机代码有实现入口、handler、注册或 UI；运行仍可能依赖 gate |
| Flag=true/false | 来自本机 `codex features list`，是 CLI 配置视图；不代表桌面账号 entitlement |
| 当前工具目录 | 本次会话向 Agent 暴露的工具定义；未逐项执行 |
| 未验证 | 没有对账户、平台、远端服务或执行结果作完整实测 |

## 2. 本机版本与架构

| 层 | 本机值 |
|---|---|
| Windows package | `26.1007.2314.0` |
| Desktop package.json | `26.1007.21434` / build `13901` / `prod` |
| Electron | `42.3.0` |
| CLI | `0.162.0-alpha.17.2` |
| 安装目录 | `C:\Program Files\WindowsApps\OpenAI.Codex_26.1007.2314.0_x64__2p2nqsd0c76g0` |
| CLI executable | `C:\Users\xiaoyu\AppData\Local\OpenAI\Codex\bin\2e5e00daee91c61d\codex.exe` |

Desktop 是 Electron 应用，核心推理/工具运行由 `codex.exe app-server` 承担。本机 Desktop 进程实际以 stdio 连接 app-server，并显式启用 code_mode_host、codex-app-tools MCP、code-review MCP。包内另有 command runner、code-mode host、Windows sandbox service/setup、rg、CUA Node 运行时。

独立 stdio initialize smoke test 已成功，那个独立服务的 Remote status 为 `disabled`。这不证明所有 Desktop/daemon 连接状态相同，也不证明官方云 relay 手机接入已可用。

## 3. 功能分类清单

### 01 聊天与历史

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 新建与恢复 | 新建聊天、无项目 standalone chat、恢复已有聊天；Temporary Chat 的命令和说明也存在，实际可用范围受产品 surface 影响。 | API / Desktop；Temporary Chat 为条件功能 |
| Fork 与继续 | 从已有聊天分叉，继续历史任务；CLI 也提供 resume / fork。 | API / Desktop / CLI |
| 历史管理 | 列表、读取、归档、反归档、删除、取消订阅，以及分页读取 turns / items。 | API / Desktop |
| 侧栏管理 | 改名、置顶、已读/未读、按项目/连接分组、手工或最近更新排序、自定义 section。 | API / Desktop / 当前 MCP 工具目录 |
| 搜索 | 聊天搜索、全文命中位置、当前聊天内查找；thread/search 和 thread/searchOccurrences 为 experimental。 | Desktop / Experimental API |
| 分享与复制 | 复制 deeplink、聊天 Markdown、最近代码块、conversation path、工作目录；共享 Codex snapshot / ChatGPT conversation 路由存在。 | Desktop；共享路由开放未验证 |
| 上下文管理 | 手动 compaction、token usage / context 指示、revert、inject_items、历史压缩与 legacy rollout 迁移。 | API / Desktop / CLI；部分 experimental |

证据索引：`API:thread/`；`UI:command-messages-`；`UI:threadHeader.`。

### 02 消息输入与响应展示

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 输入类型 | 协议支持 text、image、localImage、audio、localAudio、mention、skill；桌面允许拖放/附加文件和文件夹。 | API / Desktop |
| 上下文引用 | 通过 mention 引用文件、技能、Apps、浏览器 tab 等上下文；具体可选对象由客户端与插件决定。 | Desktop；mentions_v2 flag=true |
| 流式输出 | Agent message、plan、reasoning summary、工具进度、command output、diff、realtime transcript/audio 的增量事件。 | API |
| 富内容 | Markdown、代码块、Mermaid、图片、音频、视频、文件链接、交互 visualization、inline finding 与 artifact follow-up 的渲染入口。 | Desktop / 插件；格式依赖入口 |
| 结构化输出 | turn/start.outputSchema 可约束最终响应；CLI exec 提供 JSON 输出相关选项。 | API / CLI |

证据索引：`API:turn/start`；`Schema:UserInput`；`Schema:ThreadItem`；`UI:composer.`。

### 03 回合控制、队列与 Goal

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 回合控制 | start、steer、interrupt；运行时追加方向、停止当前回合。 | API / Desktop |
| 消息队列 | 添加、列出、编辑、删除、重排和启动队列；桌面支持 queue / steer follow-up 偏好与 background send，CLI queue 可投递已有 session。 | Desktop / CLI / Experimental API |
| 回合与线程设置 | 覆盖 model、effort、serviceTier、cwd、权限、environment、workspace roots 等；thread/settings/update 与 turn/settings/update 为 experimental。 | API；部分 experimental |
| 持续 Goal | 设置/读取/清除目标、编辑 objective、暂停/恢复、记录 tokensUsed/timeUsedSeconds；状态包括 active、paused、blocked、usageLimited、budgetLimited、complete。 | API / Desktop；goals flag=true |
| Token budget | Goal 支持可选 tokenBudget 与预算进度；不代表所有聊天都启用预算。 | API / Desktop |

证据索引：`API:turn/`；`API:thread/queue/`；`API:thread/goal/`；`UI:composer.threadGoal`。

### 04 模型与执行模式

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 模型选择 | 模型列表、能力发现、最近使用的 model/effort/speed 组合、provider capabilities。 | API / Desktop |
| Reasoning effort 与速度 | 模型声明支持的 effort，Standard / Fast / Ultrafast UI 和 service tier；实际支持由模型/provider 决定。 | Desktop；fast_mode / ultrafast_mode=true |
| Default / Plan | 协议的 collaboration mode 包含 default 与 plan；可切换计划模式。 | API / Desktop |
| Provider 与本地模型 | 自定义 model provider；CLI --oss 与 --local-provider 指向 lmstudio / ollama；本机配置使用第三方 provider。 | CLI / API；本地模型连接未实测 |
| 输出偏好 | 输出 detail、reasoning summary、web search 模式、自定义 instructions、AGENTS.md / override、tone / response style 设置入口。 | Desktop / 配置 |

证据索引：`API:model/list`；`API:modelProvider/capabilities/read`；`Schema:TurnStartParams`；`UI:settings.agent.`。

### 05 Multi-agent 与跨聊天协调

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Subagent 执行与活动 | multi_agent flag=true，协议包含 collabAgentToolCall / subAgentActivity；本次工具环境有 spawn/message/followup/interrupt/list/wait。 | Flag / Schema / 当前工具目录 |
| 跨聊天创建与读取 | create_thread、fork_thread、list_threads、read_thread、wait_threads、list_archived_threads。 | 当前 Desktop MCP 工具目录 |
| 跨聊天操作 | send_message_to_thread、改名、归档、置顶、读状态、移动项目、导航至聊天。 | 当前 Desktop MCP 工具目录 |
| 执行地点 Handoff | 在 checkout / managed worktree 之间转移任务；支持对其他 host 的 handoff 请求与状态查询，具体 host 能力取决于连接。 | Desktop MCP / worker；远程迁移未实测 |
| 旧字段兼容 | multiAgentMode 字段仍有 schema，但本版标记 deprecated / ignored，描述指向 Ultra effort 的 proactive multi-agent 行为。 | Schema 注释；不可按旧字段实现 |

证据索引：`Schema:ThreadItem`；`UI:subagent-`；`MCP:codex_app`。

### 06 Shell、Terminal 与 Process

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 命令执行 | shell / unified_exec、流式 stdout/stderr、PTY、命令状态与 exit code。 | API；相关 flags=true |
| 交互进程 | stdin 写入、resize、terminate；experimental process/spawn、writeStdin、kill、resizePty。 | API；process 为 experimental |
| 后台 Terminal | 后台命令与终端会话，列出/清理/终止 background terminals。 | Desktop / Experimental API |
| 集成 Terminal | 右侧或底部面板、terminal tab、shell 选择、读取当前线程 app terminal 输出。 | Desktop / 当前 MCP 工具目录 |
| Shell 环境 | cwd、多 writable roots、环境继承策略、shell snapshot、worktree shell environment。 | 配置 / Desktop worker |

证据索引：`API:command/exec`；`API:process/`；`API:thread/backgroundTerminals/`；`UI:terminal`。

### 07 文件系统与代码编辑

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 文件管理 API | readFile、writeFile、createDirectory、getMetadata、readDirectory、remove、copy、watch / unwatch。 | API |
| 文件导航与搜索 | 文件树/导航面板、fuzzy file search、session-based 搜索、文件内搜索、go to line。 | Desktop / API；搜索 session 为 experimental |
| 内置代码编辑 | 打开文本文件、源码编辑、tab、跳转定义、导航前进后退、Git blame。 | Desktop 代码与命令 |
| 外部打开 | 默认文件打开目标、打开 IDE / VS Code、external browser、系统文件处理关联。 | Desktop / Windows Manifest |
| 文件监视 | fs/changed 通知、编辑器与预览更新、资源 tab 与二进制 preview source。 | API / Desktop |

证据索引：`API:fs/`；`API:fuzzyFileSearch`；`UI:file-editor-`；`UI:text-file-editor-`；`UI:command-messages-`。

### 08 Git 工作流

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 仓库与分支 | 初始化 repo、识别 origins / roots、当前/默认/upstream/recent 分支、创建/checkout/search 分支、分支元数据和 ahead count。 | Desktop worker |
| Diff 与 Changes | staged / unstaged / uncommitted / branch / turn / commit diff，统计、基线切换、review panel、blame。 | Desktop worker / UI |
| Stage 与回退 | stage、unstage、revert 处理入口。 | Desktop worker |
| Commit / Push | 桌面 Commit / Push workflow、生成 commit message、自定义 commit instructions、force-with-lease 偏好。 | Desktop UI / worker |
| PR 创建与合并 | 创建 PR / draft PR、打开 GitHub PR、merge method 设置、PR instructions。 | Desktop / code-review 插件；GitHub 权限依赖账户 |
| Rebase | git-rebase 模块存在；具体 UI 路径与本机 repo 操作未执行验证。 | 代码存在；运行未验证 |

证据索引：`Worker:git`；`Worker:review-diff`；`UI:local-conversation-git-actions-`；`UI:git-settings-`。

### 09 Code Review 与 PR 管理

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 本地 Review | review/start、CLI review、localReview；对工作树/差异进行审查并显示 findings。 | API / CLI / 插件 |
| PR 浏览 | 搜索 PR、读取 metadata/body/summary/discussion/reviews、diff、revisionFile/revisionDiff、stack、reviewSnapshot、inboxDetails。 | code-review 插件注册 |
| CI 与合并状态 | checks 读取 CI diagnostics、mergeability、authoredUpdates。 | 插件；checks 当前工具目录已暴露 |
| Review 执行 | startReview、chatReview、cancelReview、setReviewFindingResolved。 | 插件注册；远端操作未调用 |
| PR 写操作 | update、merge、submitReview、comment、commentUpdate、reviewThreadUpdate；可关闭/修改 PR、提交评审、管理评论与 resolve 状态。 | 插件注册；GitHub auth / server 权限条件 |
| 监控与修复 | Watch and fix pull requests、自动修复/auto-merge 的设置与 automation 代码存在。 | Desktop 代码存在；账户开放未验证 |

证据索引：`API:review/start`；`Plugin:code-review/server.mjs`；`UI:pull-request-code-review-`。

### 10 Managed Git Worktree

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 创建与附加 | 按 ref 创建 managed worktree、attach 现有 checkout、异步创建进度、取消 pending 创建与失败重试。 | Desktop / 当前 MCP 工具目录 |
| 归档与恢复 | 保存可恢复 Git snapshot，archive / restore；记录 worktree 与 archived_worktree attachments。 | Desktop / 当前 MCP 工具目录 |
| 生命周期 | ownership、topology、root 设置、fetch upstream、自动清理数量、手动管理、恢复元数据。 | Desktop worker / settings |
| 任务搬移 | move-thread-to-local、move-thread-to-worktree、move-thread-to-host-worktree。 | Desktop worker；具体迁移条件按版本实现 |

证据索引：`MCP:codex_app`；`Worker:create-worktree`；`Worker:restore-worktree`；`UI:worktrees-settings-`。

### 11 项目、Local Environment 与 WSL

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 项目管理 | project list/read/create/import/update/move/delete；桌面 open folder / new project、多 roots、项目分组。 | Desktop / Experimental API |
| 执行 Environment | environment/add / info / status，线程/回合 environment 选择、runtimeWorkspaceRoots。 | Experimental API |
| Local Environment 配置 | local-environments 设置页、environment actions 快捷命令、worktree setup / 配置文件相关入口。 | Desktop 代码存在 |
| Windows Native / WSL | 可选 Windows native 或 WSL agent environment；WSL connections、install-wsl handler 和对应错误/状态处理。 | Desktop 代码存在；WSL 当前连接未验证 |

证据索引：`API:project/`；`API:environment/`；`UI:remote-connections-settings-`；`UI:settings.agentEnvironment`。

### 12 Cloud 执行

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Cloud Tasks | CLI cloud exec/status/list/apply/diff；桌面 cloud task / remote conversation 页面与 cloud-local location 选择。 | CLI / Desktop；账号可用性未验证 |
| Cloud Environment | 环境新建/编辑、repositories、setup 与网络策略相关设置、variables/secrets、domain-scoped secrets、共享范围与 editors。 | Desktop 代码存在；Cloud auth / workspace 条件 |
| Cloud 预览 | cloud file preview、browser live view 与控制 overlay 代码。 | 共享/Cloud 代码存在；未实测 |
| Cloud Automations | 云端 scheduled task 与 team task UI；文案描述设备离线时也能运行。 | 共享/Cloud 代码存在；账户开放未验证 |

证据索引：`CLI:codex cloud`；`UI:cloud-environment-editor-`；`UI:cloud-environments-settings-`；`UI:command-messages-`。

### 13 Remote 与设备通信

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Remote Control 管理 | enable、disable、status/read；状态 disabled / connecting / connected / errored。 | Experimental API；独立 smoke test 为 disabled |
| 设备配对 | pairing/start / status、短期 pairingCode / manualPairingCode / expiresAt，授权 client/list / revoke。 | Experimental API；未开启/配对 |
| 手机控制 UI | 包内存在 “Control this PC from your phone or other device” 文案，控制本机与访问其他设备的页签。 | Desktop 代码；依赖 account 与 slingshot gate |
| SSH | SSH connection 编辑/发现、remote CLI 登录、SSH 驱动 daemon bootstrap、连接状态与 host 上的项目。 | Desktop / CLI；连接未实测 |
| 协议传输 | app-server help 提供 stdio、Unix socket、WebSocket；TUI --remote 支持 ws/wss/unix 地址与 bearer token 环境变量。 | CLI help；Desktop 实际使用 stdio |
| Daemon | bootstrap/start/restart/update/stop/version、enable/disable remote control、stdio proxy 到控制 socket。 | CLI help |
| 独立 exec-server | 提供远程执行服务、forward 注册 environment、Noise / Direct transport、capability-token / signed-bearer-token、AWS SigV4 配置。 | CLI help；注册未实测 |
| Device identity 与锁屏控制 | device key / TPM / Secure Enclave 分支、userVerification API、locked Computer Use gate；锁屏设置文案以 Mac 为主。 | 代码 / Experimental API；平台和可用性未验证 |

证据索引：`API:remoteControl/`；`CLI:codex remote-control`；`CLI:codex exec-server`；`UI:remote-control-connections-visibility-`。

### 14 Automation 与 Heartbeat

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Local scheduled tasks | 创建/更新/查看/删除 recurring automation；ACTIVE / PAUSED 状态；local cron 每次独立运行。 | 当前 MCP 工具目录；in_app_local_automation=true |
| Thread Heartbeat | 在当前聊天定期继续工作，targetThreadId、下一次执行时间、暂停/恢复；与归档行为关联。 | Desktop / 当前 MCP 工具目录 |
| Schedule | interval、daily、weekdays、weekly、monthly、custom；RRULE 配置与 schedule UI。 | Desktop UI / handler |
| 运行配置 | prompt、project、model、reasoningEffort、运行地点、运行目标聊天、执行历史/Inbox。 | Desktop UI / handler；Cloud 项按账户 gating |
| 通知偏好 | 普通通知 / failed_runs_only、静音设置、未读 scheduled task updates。 | Desktop UI / 当前 MCP 工具 schema |

证据索引：`MCP:codex_app`；`UI:automation-frequency-section-`；`UI:automation-detail-panel-`；`UI:local-conversation-heartbeat-automation-`；`Main:automation_update`。

### 15 Skills、Plugins 与 Marketplace

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Skills | 发现/列出/读取技能、启用/禁用、extraRoots、搜索、reload、通过 skill mention 调用、MCP dependency 安装。 | API / Desktop；skill_search=true |
| Plugins | 安装/卸载、列出/读取/搜索、installed/reconcile、skill/read、启用与管理员禁用状态。 | API / Desktop；plugin/search experimental |
| Marketplace | 本地/Git marketplace 的 add/remove/upgrade；CLI marketplace list。 | API / CLI |
| Plugin Sharing | share/save、updateTargets、list、checkout、delete。 | API；plugin_sharing=true；服务端可用性依权限 |
| 远程与默认插件 | remote_plugin flag=true，openai-bundled 与 openai-primary-runtime cache。 | 本地 cache / flags |
| 模板技能 | personal artifact template 创建/修改、template browser、create/delete templates 文案。 | 已安装模板 skill；UI 开放范围未验证 |

证据索引：`API:skills/`；`API:plugin/`；`API:marketplace/`；`CLI:codex plugin`；`Plugin:cache`。

### 16 MCP、Apps 与 Dynamic Tools

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| MCP Server 接入 | STDIO / Streamable HTTP，command/args/cwd/env、headers/token env、OAuth login、reload、startup status。 | API / Desktop |
| MCP Tools 与 Resources | tool/call、resource/read、tools 发现；event stream start/stop 与 notification。 | API；event stream experimental |
| Elicitation | MCP 交互表单/URL 授权、requestUserInput、auth_elicitation、工具调用审批。 | API / flags / 当前工具环境 |
| Apps / Connectors | app read/list/installed、Apps 连接与 OAuth、按上下文提供连接器 tools。 | API / Desktop；账号权限依赖服务端 |
| MCP Apps UI | MCP app attachment / UI surface、MCP app data 清理与权限入口；enable_mcp_apps flag=false 不足以否定共享 UI 代码存在。 | Desktop 代码；实际启用路径未验证 |
| 工具编排 | 动态工具 namespace / deferred loading、工具搜索，Code Mode host、Node REPL、functions.exec 编排。 | Schema / 当前工具目录；code_mode_host=true，code_mode=false |
| Desktop MCP 桥接 | codex-app-tools server.mjs 通过 NativePipe 获取 tools/list 和调用 tools/call；调用携带 thread/turn/caller 等上下文。 | 本地插件和 Desktop handler |

证据索引：`API:mcpServer/`；`API:app/`；`UI:plugins-settings-`；`Main:tools/list`。

### 17 内置与外部 Browser

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 内置 Browser | tab、地址栏、前进/后退/reload、find、zoom、截图、打印；本地开发 URL 打开目的地设置。 | Desktop handler；in_app_browser=true |
| Agent Browser Use | 浏览器快照/DOM/截图交互、CDP handler、browser use 权限与站点范围策略；当前 cua_repl 提供 browser API。 | 插件 / Desktop；相关 flags=true |
| 网页标注与设计 | comment / selection / annotation mode、截图附带、设计 overlay 调整、将标注送到 composer。 | Desktop handler；browser_annotation_api=true |
| 浏览器数据 | history、download history/location、cookies/site permissions、cache 清理、password/contact info 设置入口。 | Desktop 代码；具体页由能力 gating |
| External Browser | Chrome/Edge 等浏览器与扩展会话控制；external browser use 插件和 flag。 | 插件 cache / 当前 browser API |
| Profile 与 Extensions | profile import、extension manager；extension 可见性还依赖额外 feature gate。 | Desktop 代码；未验证实际开放 |

证据索引：`UI:browser-use-settings-`；`UI:browser-use-settings-visibility-`；`Main:browser-sidebar-command`；`Plugin:browser/chrome/unified-computer-use`。

### 18 Computer Use 与应用集成

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Native App 控制 | Computer Use 插件与 Any App UI、应用截图/交互桥接代码。当前会话 cua_repl 明确禁用 Native computer APIs，不能据 flag=true 声称此会话可控制全部 Windows apps。 | 代码与插件存在；当前会话 Native API 禁用 |
| 应用权限 | Always-allowed apps、单应用审批与 capability 检查。 | Desktop 代码；平台条件 |
| Office Live | Excel / PowerPoint / Word add-in 设置文案；本机 spreadsheets 插件带 excel-live-control skill。 | 插件 / Desktop 代码；实际 add-in 连接未验证 |
| Messages 集成 | 按聊天保存 read/send access 的代码与设置文案。 | 共享/平台代码；Windows 与账号开放未验证 |
| 锁屏使用 | allowLockedComputerUse 配置要求 + remote control + 多重 gate；不是仅打开一个 flag 即可。 | 代码存在；平台与服务可用性未验证 |

证据索引：`UI:computer-use-settings-`；`UI:use-can-use-locked-computer-use-`；`Plugin:computer-use`；`Plugin:unified-computer-use`。

### 19 文档、表格、幻灯片与预览

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Office / PDF 生成 | documents、spreadsheets、presentations、pdf skills；在工作区生成/编辑/渲染对应文件。 | 已安装技能；依赖运行时可用性 |
| 文件预览 | DOCX、PDF、表格、slides、text/document、image 等预览组件；Notebook preview panel 存在。 | Desktop 代码；具体格式由 loader / plugin 决定 |
| 文档反馈 | DOCX annotation、redlines 显示、PDF diff、artifact feedback / review、发送修改建议到聊天。 | Desktop 代码 |
| 表格 UI | Spreadsheet editor 代码包含单元格、公式、格式与相关编辑入口；不要将包内完整 editor 等同于每个文件都能在线编辑。 | 共享/Artifact 代码；具体可用性未验证 |
| Workspace Dependencies | 读取 bundled Node.js / Python 与文档处理依赖路径、诊断/reset-install Workspace 设置。 | 当前 MCP 工具目录；workspace_dependencies=true |
| 文件类型处理器 | 指定 plugin 打开特定文件，Windows 文件关联 csv/docx/pptx/tsv/xls/xlsm/xlsx/skill。 | Desktop settings / Windows Manifest |

证据索引：`Plugin:openai-primary-runtime`；`UI:artifact-preview-`；`UI:docx-preview-panel-`；`UI:pdf-preview-panel-`；`UI:notebook-preview-panel-`。

### 20 LaTeX

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 源码与 PDF | 内置 .tex source editor、自动 PDF preview、compiler details、插入会话图片、下载 PDF。 | Desktop 代码 / 当前工具定义 |
| Compile Diagnostics | compile_latex_document 检查已保存 standalone .tex 并返回 diagnostics。 | 当前 MCP 工具目录；本次未编译 |
| 独立运行环境 | Desktop 代码为 preview 启动专用 app-server / sandbox 与 compiler transport；其工具说明不要求 terminal TeX 安装。 | 本地代码 / 工具定义；不等同离线 TeX |

证据索引：`MCP:compile_latex_document`；`Main:codex_latex_preview`；`UI:workspace-1f33ff3a545e.js`。

### 21 搜索、图像与媒体

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| Web Search | webSearch item、cached / live 等搜索策略设置；CLI --search。 | Schema / CLI / Desktop；实际工具依模型与配置 |
| Image View / Generation | 查看 local image、imageGeneration 结果、imagegen skill；图片预览与反馈组件。 | Flags=true / 当前 skill；本次未生成 |
| Visualization | visualize 插件、inline visualization；Mermaid preview、交互可视化与分享/导出依对应 surface。 | 已安装插件 / Desktop 代码 |
| 音视频显示 | 本地/远端媒体渲染入口与播放控件；媒体行为按 Desktop 工具约束。 | Desktop 渲染与工具说明 |

证据索引：`Schema:ThreadItem`；`UI:settings.agent.configuration.webSearch`；`Flags:image_generation/view_image`；`Plugin:visualize`。

### 22 Voice、Dictation 与 Appshot

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 实时 Voice | start/stop、appendAudio/Text/Speech、voice list、transcript、audio delta、realtime SDP；schema 包含 WebSocket / WebRTC / existingCall transport。 | Experimental API；in_app_voice / realtime_conversation=true |
| Voice 控件 | microphone / output mute、全局 hotkey、voice 选择、screen context capability。 | Desktop 代码；账户/平台与会话条件 |
| Dictation | composer/global dictation、hold / tap shortcuts、microphone 选择、dictionary、录音 history/recovery/retry/download/delete。 | Desktop 代码；in_app_dictation=true；当前配置可能受限 |
| Appshot / Screen Selection | Appshot visual + text、选择区域截图到当前/新聊天、destination 与 sound 设置、Mini destination。 | Desktop 代码；平台能力未逐项验证 |
| Voice 屏幕上下文 | capture_screen_context 工具当前只允许 active voice chat，且当前设备仅支持 Codex foreground page/sidebar。 | 当前工具定义；范围有明确限制 |

证据索引：`API:thread/realtime/`；`UI:voice-settings-`；`UI:appshots-settings-`；`Main:global-dictation`。

### 23 Hooks、导入与个性化

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 生命周期 Hooks | preToolUse、permissionRequest、postToolUse、preCompact、postCompact、sessionStart、sessionEnd、userPromptSubmit、subagentStart、subagentStop、stop、interrupt。 | API / Desktop；hooks=true |
| Hook 管理 | global/project/plugin sources、trust/review、reload、加载问题和配置层覆盖显示。 | Desktop UI / 配置 |
| 外部 Agent 导入 | detect/import/history/progress；配置/指令/skills/plugins/MCP/subagents/hooks/commands/memory/sessions 类型；UI 有 Claude Code、Claude Cowork、Cursor 来源与保持同步代码。 | API / Desktop；导入能力按来源与 flag 区分 |
| 自定义 Instructions | AGENTS.md 编辑、override 提示、同步 Codex instructions、输出 style / personality 设置入口。旧 personality 字段已 deprecated。 | Desktop / Schema |
| Codex Memory | memory/status/reset 与 per-thread memoryMode、memory settings；本机 memories flag=false。 | 代码 / Experimental API；CLI flag 未启用 |
| Computer History / Chronicle | 活动文字摘要、pause/resume、include/exclude apps/websites、清除记录。chronicle flag=false，且 settings 有能力检查。 | 代码存在；本机 CLI flag 未启用 |

证据索引：`API:hooks/list`；`API:externalAgentConfig/`；`UI:hooks-settings-`；`UI:import-settings-`；`UI:personalization-settings-`。

### 24 权限、Sandbox 与账号

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 权限边界 | read-only / workspace-write / danger-full-access，文件读写 roots、网络权限、permissions profiles 与 configRequirements。 | API / CLI / 配置 |
| 人工与自动审批 | command/fileChange/permissions/requestUserInput/MCP elicitation；审批 reviewer user / auto_review / legacy guardian_subagent、guardian denied action approval API。 | API / Desktop；guardian_approval=true |
| Windows Sandbox | setupStart / readiness / setupCompleted、Windows service/setup binaries；新 windows_sandbox_service flag=false 不代表全部 sandbox 不存在。 | API / 安装文件 |
| Authentication | CLI API key、ChatGPT browser/device login 与 auth token；gatewayOAuth、logout/refresh、secret_auth_storage；Bedrock setup/discover/checkGovCloudRequirements experimental。 | API / CLI；各登录方式未全部实测 |
| User Verification | status/enroll/delete/verify/cancel 与 attestation server request。 | Experimental API；未验证服务开放 |
| Usage 与 Limits | rateLimits、usage、reset credit、workspaceMessages、credits 提示相关 API；billing/analytics UI 受登录与 plan gate。 | API / Desktop；账户条件 |

证据索引：`API:permissionProfile/list`；`Schema:ApprovalsReviewer`；`API:account/`；`API:windowsSandbox/`。

### 25 Desktop UI、Windows 集成与 Mini

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| 窗口与布局 | 多窗口、新 window、聊天 popout/side chat、右侧/底部/全视图、tab 切换/重开/关闭、缩放、快捷命令菜单。 | Desktop 代码 / native menu |
| 导航与活动 | sidebar、pinned summary、activity view、跳转需要注意的聊天、recent chat 快捷键、read/unread。 | Desktop 代码 / 当前 MCP 工具目录 |
| Appearance | light/dark/system、颜色/contrast/字体与大小、code theme、theme import/export、reduce motion、translucent sidebar。 | Desktop settings 代码 |
| 通知与声音 | 完成/审批/问题通知、仅 unfocused 或 always、自定义 notification sound、Inbox 和 badge。 | Desktop settings / handlers |
| Mini / Pets | Mini overlay、pet/avatar 选择与尺寸、custom pet 安装/创建/刷新、画中画；会话/voice/dictation 关联入口。 | Desktop 代码；具体入口受平台与 gate |
| Windows 系统集成 | codex:// deeplink、目录右键 OpenProjectInCodex、开机启动、Copilot key、文件关联、sandbox service manifest。 | Windows Manifest |
| 设置与语言 | keyboard shortcuts 自定义、UI language、default file target、integrated terminal shell、projectless task folder、follow-up/send 偏好。 | Desktop settings 代码 |

证据索引：`UI:command-messages-`；`Main:electron-set-window-mode`；`UI:pets-settings-route-`；`Manifest:Windows`。

### 26 维护、诊断与数据

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| App / CLI 更新 | Desktop update check、in-app updates、CLI update；Windows Store eligibility 有平台限制。 | CLI / 当前 MCP 工具目录；本次未检查更新 |
| 诊断与性能 | doctor、debug、server/diagnostics、trace recording、task manager/performance trace、debug panel、renderer / connection logs。 | CLI / Experimental API / Desktop 代码 |
| Feedback | feedback/upload、Desktop feedback、artifact 附件反馈。 | API / Desktop；本次未上传 |
| Storage 与 Cleanup | archived chats 管理、旧 chat / subagent 清理、worktree prune / restore、rollout compression / migrate。 | Desktop / API / CLI |
| 配置管理 | config/read、value/write、batchWrite、configRequirements/read、features inspect/enablement、分层 profile。 | API / CLI / Desktop |

证据索引：`CLI:codex doctor`；`CLI:codex update`；`API:server/diagnostics`；`API:feedback/upload`；`UI:settings.storage`；`Main:toggle-trace-recording`。

### 27 共享代码与条件功能

| 功能 | 内容 | 本机证据/状态 |
|---|---|---|
| ChatGPT Chat / Work | shared UI 包含 Chat/Work/Codex 切换、ChatGPT projects、cloud/local Work、conversation sharing 和 account/profile 设置。 | 共享代码存在；当前账户开放未验证 |
| Pages / Canvas | Page editor、格式化/链接/模板、Canvas 与 rectangle/circle/arrow/line/text/note 工具、artifact editor 入口。 | 共享代码存在；不能全算当前 Codex 已启用 |
| Sites / Appgen | site 生成、编辑、preview、publication/share/access、database、site automation 模块。 | 共享代码存在；服务与权限未验证 |
| Dots / Teams | openOrbit.dot / dotsHome、team workspace、join/create/team plugins 等代码。 | 共享代码存在；功能开放未验证 |
| Meetings | Meetings: Take notes 快捷命令与相关共享代码。 | 命令存在；平台与账户能力未验证 |
| Codex Micro | 外设 agent keys、command keys、analog stick、knob、microphone、lighting、keycap/skill/chat mappings 和 mini games 模块。 | 代码存在；硬件与 feature gate 未验证 |
| Debug / 实验遗留 | Daybreak、GPU compositor isolation、confetti/audio visualizer 等 settings；removed/deprecated flags 与 mock API 留存。 | 代码/实验入口；不计为默认生产能力 |

证据索引：`UI:command-messages-`；`UI:use-visible-settings-sections-`；`UI:appgen-`；`UI:codex-micro-settings-`。

## 4. 本机插件与扩展

版本化 cache 中识别到下列插件，已排除安装临时目录、backup 和 latest alias。cache 存在与启用/服务启动是不同证据；codex-app-tools / code-review 在 Desktop 启动参数中明确启用，其余插件在本次配置/skills 中可见。

| Marketplace | Plugin | Version |
|---|---|---|
| openai-bundled | browser | 26.1007.21434 |
| openai-bundled | chrome | 26.1007.21434 |
| openai-bundled | code-review | 26.1007.21434 |
| openai-bundled | codex-app-tools | 0.1.6 |
| openai-bundled | computer-use | 26.1007.21434 |
| openai-bundled | unified-computer-use | 26.1007.21434 |
| openai-bundled | visualize | 1.0.49 |
| openai-primary-runtime | documents | 26.1011.11113 |
| openai-primary-runtime | pdf | 26.1011.11113 |
| openai-primary-runtime | presentations | 26.1011.11113 |
| openai-primary-runtime | spreadsheets | 26.1011.11113 |
| openai-primary-runtime | template-creator | 26.1011.11113 |

System skills：imagegen、openai-docs、skill-creator、skill-installer。用户安装的 api-sec、auth-sec、business-logic-vuln、file-access-vuln、injection-checking、recon-for-sec、src-hunter 等安全技能是用户扩展，不能算 Codex 原生安全测试产品功能。

### 当前 Desktop MCP 工具目录

以下名称在本次会话工具目录中可见，未全部执行：

```text
archive_worktree
attach_artifact
attach_worktree
automation_update
capture_screen_context
check_app_update
compile_latex_document
create_thread
create_worktree
end_realtime_voice_call
fork_thread
get_handoff_status
get_worktree_creation_status
handoff_thread
list_archived_threads
list_artifacts
list_projects
list_threads
load_workspace_dependencies
move_thread_to_project
navigate_to_codex_page
open_in_codex
read_thread
read_thread_terminal
remove_artifact
restore_worktree
send_message_to_thread
set_thread_archived
set_thread_pinned
set_thread_read_state
set_thread_title
update_sidebar_preferences
wait_threads
```

### code-review 插件注册方法

这些名称来自本地 `server.mjs` 的注册代码，包含动态循环生成的 body/discussion/metadata/reviews/summary；完整 server 注册不等同全部方法都会在当前上下文向 Agent 暴露。

```text
list_files
pull_requests.account
pull_requests.authoredUpdates
pull_requests.avatar
pull_requests.body
pull_requests.cancelReview
pull_requests.chatReview
pull_requests.checks
pull_requests.comment
pull_requests.commentUpdate
pull_requests.diff
pull_requests.discussion
pull_requests.inboxDetails
pull_requests.localReview
pull_requests.media
pull_requests.merge
pull_requests.mergeability
pull_requests.metadata
pull_requests.reviewSnapshot
pull_requests.reviewThreadUpdate
pull_requests.reviews
pull_requests.revisionDiff
pull_requests.revisionFile
pull_requests.search
pull_requests.setReviewFindingResolved
pull_requests.stack
pull_requests.startReview
pull_requests.submitReview
pull_requests.summary
pull_requests.update
pull_requests.userSearch
read_diff
read_file
```

## 5. Feature flags 快照

所有 flag 按本机输出列出。`removed` 表示旧开关退出控制路径，不能据它为 false 推断功能不存在，例如 Remote Control API 已存在；deprecated/under development 也不代表 UI 已开放。

共 167 个 flag：under development 66、experimental 4、stable 52、removed 41、deprecated 4。

| Flag | Stage | 本机 CLI 值 |
|---|---|---|
| `agent_message_board` | under development | false |
| `analytics_plan_history` | experimental | false |
| `api_key_cyber_access_programs` | stable | false |
| `api_key_model_discovery` | stable | true |
| `apply_patch_freeform` | removed | false |
| `apply_patch_preserve_line_endings` | removed | false |
| `apply_patch_streaming_events` | under development | false |
| `apps` | stable | true |
| `apps_mcp_path_override` | removed | false |
| `artifact` | under development | false |
| `auth_elicitation` | stable | true |
| `background_paginated_rollout_migration` | under development | false |
| `bedrock_setup_wizard` | under development | false |
| `browser_annotation_api` | stable | true |
| `browser_use` | stable | true |
| `browser_use_external` | stable | true |
| `browser_use_full_cdp_access` | stable | true |
| `chronicle` | under development | false |
| `cli_daybreak` | under development | false |
| `code_mode` | under development | false |
| `code_mode_buffered_exec` | removed | false |
| `code_mode_host` | stable | true |
| `code_mode_interrupt` | under development | false |
| `code_mode_only` | under development | false |
| `code_mode_only_strict_3p_tools` | under development | false |
| `code_mode_prewarm` | under development | false |
| `code_mode_tool_search` | under development | false |
| `codex_apps_mcp_2026_07_28` | under development | false |
| `codex_git_commit` | removed | false |
| `collaboration_modes` | removed | true |
| `compaction_image_budget` | stable | true |
| `computer_use` | stable | true |
| `concurrent_reasoning_summaries` | under development | false |
| `content_item_kinds` | stable | true |
| `context_management` | under development | false |
| `current_time_reminder` | under development | false |
| `cwd_relative_turn_diffs` | under development | false |
| `daemon_auto_start` | stable | true |
| `default_mode_request_user_input` | under development | false |
| `defer_mailbox_preemption` | under development | false |
| `deferred_executor` | under development | false |
| `deferred_tool_world_state` | under development | false |
| `elevated_windows_sandbox` | removed | false |
| `enable_fanout` | removed | false |
| `enable_mcp_apps` | under development | false |
| `enable_request_compression` | stable | true |
| `exec_permission_approvals` | under development | false |
| `executed_tool_call_metadata` | under development | false |
| `executor_capability_discovery` | under development | false |
| `experimental_windows_sandbox` | removed | false |
| `external_agent_memory_import` | under development | false |
| `external_migration` | removed | false |
| `fast_mode` | stable | true |
| `goals` | stable | true |
| `guardian_approval` | stable | true |
| `guardian_conversation_history_tools` | under development | false |
| `guardian_enhanced_node_repl_transcripts` | under development | false |
| `guardian_ext` | removed | false |
| `guardian_node_repl_transcript_images` | under development | false |
| `guardian_reuse_parent_compaction` | stable | true |
| `guardian_root_handoff_context` | under development | false |
| `guardianv2` | under development | false |
| `guardianv2.thread_context` | removed | false |
| `guardianv2_decisions_comparison` | under development | false |
| `hooks` | stable | true |
| `image_detail_original` | removed | false |
| `image_generation` | stable | true |
| `image_resize_notice` | under development | false |
| `in_app_browser` | stable | true |
| `in_app_chat` | stable | true |
| `in_app_dictation` | stable | true |
| `in_app_local_automation` | stable | true |
| `in_app_updates` | stable | true |
| `in_app_voice` | stable | true |
| `incremental_tools` | under development | false |
| `instant_interrupt` | under development | false |
| `item_ids` | removed | true |
| `js_repl` | removed | false |
| `js_repl_tools_only` | removed | false |
| `local_thread_store_compression` | under development | false |
| `local_thread_store_shared_compression` | removed | false |
| `login_shell_package_path` | experimental | false |
| `mcp_2026_07_28` | under development | false |
| `mcp_oauth_refresh_coordination` | under development | false |
| `memories` | stable | false |
| `mentions_v2` | stable | true |
| `model_catalog_in_context` | under development | false |
| `multi_agent` | stable | true |
| `multi_agent_mode` | removed | false |
| `multi_agent_v2` | stable | false |
| `multi_agent_v2_dynamic_tools` | under development | false |
| `network_proxy` | experimental | false |
| `non_prefixed_mcp_tool_names` | under development | false |
| `nonfatal_clock_read_errors` | under development | false |
| `omit_app_server_notification_media` | under development | false |
| `personality` | removed | false |
| `plugin_hooks` | removed | false |
| `plugin_sharing` | stable | true |
| `plugins` | stable | true |
| `powershell_shell_version` | under development | false |
| `prefer_mxc` | under development | false |
| `prevent_idle_sleep` | experimental | false |
| `psp` | under development | false |
| `realtime_conversation` | stable | true |
| `reasoning_effort_override` | under development | false |
| `recommended_plugins` | stable | false |
| `remote_compaction_v2` | removed | false |
| `remote_control` | removed | false |
| `remote_models` | removed | false |
| `remote_plugin` | stable | true |
| `request_permissions_tool` | under development | false |
| `request_rule` | removed | false |
| `resize_all_images` | removed | true |
| `respect_system_proxy` | under development | false |
| `responses_websockets` | removed | false |
| `responses_websockets_v2` | removed | false |
| `retain_client_developer_messages` | under development | false |
| `rollout_budget` | under development | false |
| `runtime_metrics` | under development | false |
| `search_tool` | removed | false |
| `secret_auth_storage` | stable | true |
| `send_async_message` | removed | false |
| `send_message_to_user_async` | under development | false |
| `shell_snapshot` | stable | true |
| `shell_snapshot_v2` | under development | false |
| `shell_tool` | stable | true |
| `shell_zsh_fork` | under development | false |
| `skill_env_var_dependency_prompt` | removed | false |
| `skill_mcp_dependency_install` | stable | true |
| `skill_search` | stable | true |
| `skip_host_skill_discovery` | under development | false |
| `sleep_tool` | stable | true |
| `sqlite` | removed | true |
| `stable_environment_tools` | under development | false |
| `standalone_web_search` | under development | false |
| `steer` | removed | true |
| `step_model_switching` | under development | false |
| `system_proxy_fallback` | stable | true |
| `terminal_resize_reflow` | removed | true |
| `terminal_visualization_instructions` | under development | false |
| `token_budget` | under development | false |
| `tool_call_mcp_elicitation` | stable | true |
| `tool_search` | removed | false |
| `tool_search_always_defer_mcp_tools` | removed | true |
| `tool_suggest` | stable | true |
| `transcript_v2` | deprecated | false |
| `tui_app_server` | removed | true |
| `ultrafast_mode` | stable | true |
| `unavailable_dummy_tools` | removed | false |
| `unbounded_connection_retries` | stable | true |
| `undo` | removed | false |
| `unified_exec` | stable | true |
| `unified_exec_tty` | stable | true |
| `unified_exec_zsh_fork` | removed | true |
| `unified_image_budget` | under development | false |
| `use_agent_identity` | under development | false |
| `use_legacy_landlock` | deprecated | false |
| `use_linux_sandbox_bwrap` | removed | false |
| `use_xaa` | under development | false |
| `view_image` | stable | true |
| `web_search_cached` | deprecated | false |
| `web_search_request` | deprecated | false |
| `windows_sandbox_service` | under development | false |
| `workspace_dependencies` | stable | true |
| `workspace_owner_usage_nudge` | removed | false |
| `worktrees` | stable | true |
| `write_stdin_approval` | stable | true |

注意：`memories=false`、`chronicle=false`、`multi_agent_v2=false`、`code_mode=false`；同时 `multi_agent=true`、`code_mode_host=true`、浏览器/Computer Use/Voice/Automation 等多个基础 flag 为 true。当前 cua_repl Native computer APIs 仍明确禁用，说明 flag 与会话实际能力必须分开判断。

## 6. CLI 功能入口

下列顶层命令由本机 help 确认：

```text
agents, exec, review, login, logout, mcp, plugin, app-server, remote-control, app,
completion, update, doctor, sandbox, debug, apply, resume, queue, archive, delete,
migrate-rollouts, unarchive, fork, cloud, exec-server, features, help
```

- `app-server`：运行服务、daemon、stdio proxy、TypeScript bindings、JSON Schema generation。
- `remote-control`：start / stop / pair。
- `cloud`：exec / status / list / apply / diff。
- `exec-server`：远程执行服务与 forward environment 注册。
- `plugin`：add / list / remove / marketplace；marketplace add / list / upgrade / remove。
- `mcp`：外部 MCP server 管理与认证。
- 全局选项包括远程 endpoint、token env、model/provider、sandbox/approval、profile、cwd、多目录、worktree、search、strict config、daemon 行为等。

## 7. 全部生成的 app-server 协议方法

下面按方向列出全部方法。`[E]` 表示只在 `--experimental` 完整 schema 中出现，`[T]` 表示测试专用。未标 `[E]` 只说明出现在默认 schema，不作 stable API 保证；默认方法内部也可能包含 experimental 字段。

生成方式：

```powershell
codex app-server generate-json-schema --out <default-output>
codex app-server generate-json-schema --experimental --out <experimental-output>
codex app-server generate-ts --help
```

客户端通过 initialize capabilities.experimentalApi 声明 experimental API。完整参数、required fields 在随附 CSV/JSON，完整 JSON Schema 在 ZIP。

### ClientRequest（170）

```text
    initialize
[E] server/diagnostics
[E] userVerification/status
[E] userVerification/enroll
[E] userVerification/delete
[E] userVerification/verify
[E] userVerification/cancel
    thread/start
    thread/resume
    thread/fork
    thread/archive
    thread/delete
    thread/unsubscribe
[E] thread/increment_elicitation
[E] thread/decrement_elicitation
    thread/name/set
[E] thread/prediction/request
    thread/goal/set
    thread/goal/get
    thread/goal/clear
[E] thread/queue/add
[E] thread/queue/list
[E] thread/queue/update
[E] thread/queue/delete
[E] thread/queue/reorder
[E] thread/queue/start
    thread/metadata/update
    thread/attachment/add
    thread/attachment/list
    thread/attachmentOwner/list
    thread/attachment/remove
    thread/section/move
[E] thread/settings/update
[E] thread/memoryMode/set
[E] memory/status
[E] memory/reset
[E] rollout/compress
    thread/unarchive
    thread/compact/start
    thread/shellCommand
    thread/approveGuardianDeniedAction
[E] thread/backgroundTerminals/clean
[E] thread/backgroundTerminals/list
[E] thread/backgroundTerminals/terminate
    thread/revert
    thread/list
[E] project/list
[E] project/read
[E] project/create
[E] project/import
[E] project/update
[E] project/move
[E] project/delete
    threadSection/list
    threadSection/create
    threadSection/update
    threadSection/delete
[E] thread/search
[E] thread/searchOccurrences
    thread/loaded/list
    thread/read
    thread/turns/list
    thread/items/list
    thread/inject_items
    skills/list
    skills/extraRoots/set
    hooks/list
    marketplace/add
    marketplace/remove
    marketplace/upgrade
    plugin/list
[E] plugin/search
    plugin/installed
    plugin/reconcile
    plugin/read
    plugin/skill/read
    plugin/share/save
    plugin/share/updateTargets
    plugin/share/list
    plugin/share/checkout
    plugin/share/delete
    app/read
    app/list
    app/installed
    fs/readFile
    fs/writeFile
    fs/createDirectory
    fs/getMetadata
    fs/readDirectory
    fs/remove
    fs/copy
    fs/watch
    fs/unwatch
    skills/config/write
    plugin/install
    plugin/uninstall
    turn/start
[E] turn/settings/update
    turn/steer
    turn/interrupt
[E] thread/realtime/start
[E] thread/realtime/appendAudio
[E] thread/realtime/appendText
[E] thread/realtime/appendSpeech
[E] thread/realtime/stop
[E] thread/timeline/list
[E] thread/realtime/listVoices
    review/start
    model/list
    account/gatewayOAuth/read
    account/gatewayOAuth/login
    account/gatewayOAuth/cancel
    modelProvider/capabilities/read
    experimentalFeature/list
    permissionProfile/list
    experimentalFeature/enablement/set
[E] remoteControl/enable
[E] remoteControl/disable
[E] remoteControl/status/read
[E] remoteControl/pairing/start
[E] remoteControl/pairing/status
[E] remoteControl/client/list
[E] remoteControl/client/revoke
[E] collaborationMode/list
[T] mock/experimentalMethod
[E] environment/add
[E] environment/info
[E] environment/status
    mcpServer/oauth/login
    config/mcpServer/reload
    mcpServerStatus/list
    mcpServer/resource/read
[E] mcpServer/event/stream/start
[E] mcpServer/event/stream/stop
    mcpServer/tool/call
    windowsSandbox/setupStart
    windowsSandbox/readiness
    account/login/start
[E] account/bedrock/discover
[E] account/bedrock/setup
[E] account/bedrock/checkGovCloudRequirements
    account/login/cancel
    account/logout
    account/rateLimits/read
    account/rateLimitResetCredit/consume
    account/usage/read
    account/workspaceMessages/read
    account/sendAddCreditsNudgeEmail
    feedback/upload
    command/exec
    command/exec/write
    command/exec/terminate
    command/exec/resize
[E] process/spawn
[E] process/writeStdin
[E] process/kill
[E] process/resizePty
    config/read
    externalAgentConfig/detect
    externalAgentConfig/import
    externalAgentConfig/import/recordHistory
    externalAgentConfig/import/readHistories
    config/value/write
    config/batchWrite
    configRequirements/read
    account/read
    fuzzyFileSearch
[E] fuzzyFileSearch/sessionStart
[E] fuzzyFileSearch/sessionUpdate
[E] fuzzyFileSearch/sessionStop
```

### ServerRequest（11）

```text
    item/commandExecution/requestApproval
    item/fileChange/requestApproval
    item/tool/requestUserInput
    mcpServer/elicitation/request
    item/permissions/requestApproval
    item/tool/call
    account/chatgptAuthTokens/refresh
    attestation/generate
[E] currentTime/read
    applyPatchApproval
    execCommandApproval
```

### ServerNotification（84）

```text
    error
    thread/started
    thread/status/changed
    thread/archived
    thread/deleted
    thread/unarchived
    thread/closed
    thread/reverted
    skills/changed
    thread/name/updated
    thread/attachment/updated
    thread/goal/updated
    thread/prediction/updated
    thread/goal/cleared
    thread/queue/changed
    project/changed
    thread/project/updated
    thread/environment/connected
    thread/environment/disconnected
    thread/settings/updated
    thread/tokenUsage/updated
    turn/started
    hook/started
    turn/completed
    hook/completed
    turn/diff/updated
    turn/plan/updated
    item/started
    item/autoApprovalReview/started
    item/autoApprovalReview/completed
    autoApprovalReview/strictReviewRequired
    item/completed
    item/agentMessage/delta
    item/plan/delta
    command/exec/outputDelta
    process/outputDelta
    process/exited
    item/commandExecution/outputDelta
    item/commandExecution/terminalInteraction
    item/fileChange/outputDelta
    item/fileChange/patchUpdated
    serverRequest/resolved
    item/mcpToolCall/progress
    mcpServer/oauthLogin/completed
    mcpServer/startupStatus/updated
    mcpServer/event/stream/notification
    account/updated
    account/gatewayOAuth/changed
    account/rateLimits/updated
    app/list/updated
    remoteControl/status/changed
    externalAgentConfig/import/progress
    externalAgentConfig/import/completed
    fs/changed
    item/reasoning/summaryTextDelta
    item/reasoning/summaryPartAdded
    item/reasoning/textDelta
    thread/compacted
    model/rerouted
    model/verification
    modelProvider/authRecoveryStarted
    modelProvider/authRecoveryCompleted
    turn/moderationMetadata
    model/safetyBuffering/updated
    warning
    guardianWarning
    deprecationNotice
    configWarning
    fuzzyFileSearch/sessionUpdated
    fuzzyFileSearch/sessionCompleted
    thread/realtime/started
    thread/realtime/itemAdded
    thread/realtime/item/started
    thread/realtime/item/transcript/delta
    thread/realtime/item/completed
    thread/realtime/transcript/delta
    thread/realtime/transcript/done
    thread/realtime/outputAudio/delta
    thread/realtime/sdp
    thread/realtime/error
    thread/realtime/closed
    windows/worldWritableWarning
    windowsSandbox/setupCompleted
    account/login/completed
```

### ClientNotification（1）

```text
    initialized
```

## 8. UI 快捷命令目录

提取到 182 个 `codex.command.*` 命令标签。这是定义目录，包含 shared ChatGPT、平台专用和 gated 命令；它不是本机已开放命令列表。

| Command ID | 包内标签 |
|---|---|
| `navigateBack` | Back |
| `navigateForward` | Forward |
| `git.toggleBlame.disable` | Disable Git blame |
| `git.toggleBlame.enable` | Enable Git blame |
| `gitReview.lastTurnOnly` | Disable Git-based diffs |
| `gitReview.full` | Enable Git-based diffs |
| `gitReview.lastTurnOnlyDescription` | Only show Last Turn in the Changes panel |
| `gitReview.fullDescription` | Restore Git-based diff sources |
| `theme` | Theme |
| `switchTheme.dark` | Switch to dark theme |
| `switchTheme.light` | Switch to light theme |
| `switchTheme.darkPresetDescription` | Dark color theme |
| `switchTheme.lightPresetDescription` | Light color theme |
| `importExternalAgent.alreadyRunning` | Import is already running |
| `importExternalAgent.noCompatibleImports` | No compatible imports found |
| `importExternalAgent.noCompatibleAgentDataDescription` | {appName} couldn’t find compatible data from another coding agent |
| `importExternalAgent.loading` | Checking for imports |
| `importExternalAgent.error` | Couldn’t check for imports |
| `importExternalAgent.retry` | Try again |
| `hideMiniOverlay` | Hide Mini |
| `showMiniOverlay` | Show Mini |
| `wakeMiniOverlay` | Wake Mini |
| `composer.captureAppshot` | Capture appshot |
| `openOrbit.dot` | Open your dot |
| `focusPageBlockControls` | Focus content controls |
| `realtimeVoice.endCall` | End Voice Chat |
| `realtimeVoice` | Voice Chat hotkey |
| `realtimeVoice.toggleMicrophoneMute` | Toggle Voice Chat microphone |
| `realtimeVoice.toggleOutputMute` | Toggle Voice Chat audio |
| `importExternalAgent` | Import from other AI apps |
| `personalitySettings` | Personality |
| `toggleWorkspaceTabs` | Switch between Chat and tabs |
| `meetings.takeNotes` | Meetings: Take notes |
| `screenshotToCurrentChat` | Screenshot selection to current chat |
| `screenshotToNewChat` | Screenshot selection to new chat |
| `artifacts.selectTool` | Artifacts: Select |
| `artifacts.handTool` | Artifacts: Pan |
| `canvas.prompt` | Canvas: Ask ChatGPT |
| `artifacts.rectangleTool` | Artifacts: Rectangle |
| `artifacts.circleTool` | Artifacts: Circle |
| `artifacts.arrowTool` | Artifacts: Arrow |
| `artifacts.lineTool` | Artifacts: Line |
| `artifacts.textTool` | Artifacts: Text |
| `artifacts.noteTool` | Artifacts: Note |
| `page.formatNumberedList` | Numbered list |
| `page.formatBulletedList` | Bulleted list |
| `page.formatChecklist` | Checklist |
| `newThread` | New chat |
| `newProjectlessTask` | New standalone chat |
| `temporaryChat` | New Temporary Chat |
| `openThreadInNewWindow` | Open in new window |
| `archiveThread` | Archive chat |
| `deleteChat` | Delete chat |
| `markThreadUnread` | Mark as unread |
| `toggleThreadPin` | Toggle pin |
| `copyPageLink` | Copy Page link |
| `copyConversationMarkdown` | Copy as Markdown |
| `copyLastCodeBlock` | Copy last code block |
| `openSideChat` | Open side chat |
| `focusMainChat` | Focus main chat |
| `focusSideChat` | Focus side chat |
| `openControlWindow` | Open control window |
| `toggleDebugModal` | Toggle debug panel |
| `undoAppAction` | Undo last action |
| `redoAppAction` | Redo last action |
| `reopenClosedTab` | Reopen closed tab |
| `composer.openModelPicker` | Select effort |
| `composer.openRecentModels` | Open recent models |
| `composer.openProjectPicker` | Open project picker |
| `composer.startVoiceMode` | Toggle voice chat |
| `composer.submit` | Send message |
| `browser.toggleAnnotationMode` | Toggle annotation mode |
| `artifact.sendAnnotations` | Send annotations |
| `composer.submitInBackground` | Send message in background |
| `composer.steer` | Steer prompt |
| `composer.queue` | Queue prompt |
| `composer.clear` | Clear prompt |
| `composer.addPhotos` | Add photos |
| `composer.addFiles` | Attach files and folders |
| `composer.toggleFastMode` | Cycle speed |
| `composer.increaseReasoningEffort` | Increase reasoning effort |
| `composer.decreaseReasoningEffort` | Decrease reasoning effort |
| `composer.cycleReasoningEffort` | Cycle reasoning effort |
| `composer.togglePlanMode` | Toggle plan mode |
| `composer.toggleWorktreeMode` | Toggle Local/Worktree |
| `composer.cycleHost` | Cycle host |
| `composer.toggleWorkRunLocation` | Toggle Cloud/Local |
| `approval.approve` | Approve request |
| `approval.decline` | Decline request |
| `git.commit` | Commit or push |
| `git.createPullRequest` | Create PR |
| `git.createDraftPullRequest` | Create draft PR |
| `git.createBranch` | Create branch |
| `git.mergePullRequest` | Merge PR |
| `git.openPullRequest` | Open PR on GitHub |
| `git.toggleBlame` | Toggle Git blame |
| `forkThread` | Fork chat |
| `searchChats` | Switch chat… |
| `togglePriorityFilter` | Toggle activity view |
| `nextThreadNeedingAttention` | Next chat needing attention |
| `previousThread` | Previous chat |
| `previousTab` | Previous tab |
| `previousRecentThread` | Previous recently viewed chat |
| `nextThread` | Next chat |
| `nextTab` | Next tab |
| `nextRecentThread` | Next recently viewed chat |
| `recentThread1` | Go to recent chat 1 |
| `recentThread2` | Go to recent chat 2 |
| `recentThread3` | Go to recent chat 3 |
| `recentThread4` | Go to recent chat 4 |
| `recentThread5` | Go to recent chat 5 |
| `recentThread6` | Go to recent chat 6 |
| `switchToChat` | Switch to Chat |
| `switchToWork` | Switch to Work |
| `switchToCodex` | Switch to Codex |
| `settings` | Settings |
| `codexMicroSettings` | Codex Micro setup |
| `mcpSettings` | MCP |
| `keyboardShortcuts` | Keyboard shortcuts |
| `showKeyboardShortcuts` | Show keyboard shortcuts |
| `clearAllUnreads` | Clear all unreads |
| `manageTasks` | Manage scheduled tasks |
| `forceReloadSkills` | Force reload skills |
| `openSkills` | Go to skills |
| `newProject` | New project |
| `openFolder` | Open folder |
| `toggleSidebar` | Toggle sidebar |
| `toggleBottomPanel` | Toggle bottom panel |
| `togglePinnedSummary` | Toggle pinned summary |
| `toggleTerminal` | Open terminal |
| `openBrowserTab` | Open browser tab |
| `closeOtherTabs` | Close other tabs |
| `showWorkspaceTabView` | Full view |
| `stepWorkspaceLayout` | Cycle workspace layout |
| `openReviewTab` | Open Changes tab |
| `toggleReviewTab` | Toggle Changes |
| `toggleReviewPanel` | Toggle Changes panel |
| `toggleMaximizeSidePanel` | Toggle maximize side panel |
| `file.goToDefinition` | Go to definition |
| `file.navigateBack` | Go back in file navigation |
| `file.navigateForward` | Go forward in file navigation |
| `findInThread` | Find |
| `goToLine` | Go to line |
| `focusBrowserAddressBar` | Focus browser address bar |
| `navigateBrowserBack` | Browser back |
| `navigateBrowserForward` | Browser forward |
| `logOut` | Log out |
| `feedback` | Feedback |
| `environmentAction1` | Environment action 1 |
| `environmentAction2` | Environment action 2 |
| `environmentAction3` | Environment action 3 |
| `environmentAction4` | Environment action 4 |
| `environmentAction5` | Environment action 5 |
| `environmentAction6` | Environment action 6 |
| `environmentAction7` | Environment action 7 |
| `environmentAction8` | Environment action 8 |
| `environmentAction9` | Environment action 9 |
| `hotkeyWindow` | Popout Window hotkey |
| `globalDictationHold` | Dictation shortcut |
| `globalDictationSingleTap` | Single-tap dictation |
| `spotlightSearch` | Spotlight search |
| `notchVoice` | Voice in Mini |
| `toggleNotch` | Toggle Notch |
| `focusTab1` | Focus tab 1 |
| `focusTab2` | Focus tab 2 |
| `focusTab3` | Focus tab 3 |
| `focusTab4` | Focus tab 4 |
| `focusTab5` | Focus tab 5 |
| `focusTab6` | Focus tab 6 |
| `focusTab7` | Focus tab 7 |
| `focusTab8` | Focus tab 8 |
| `focusTab9` | Focus tab 9 |
| `thread1` | Go to chat 1 |
| `thread2` | Go to chat 2 |
| `thread3` | Go to chat 3 |
| `thread4` | Go to chat 4 |
| `thread5` | Go to chat 5 |
| `thread6` | Go to chat 6 |
| `thread7` | Go to chat 7 |
| `thread8` | Go to chat 8 |
| `thread9` | Go to chat 9 |
| `toggleBrowserPanel` | Toggle browser panel |

## 9. 对手机客户端的实际含义

可复用的核心协议是 app-server。它能表达聊天/回合、执行、文件、审批、模型配置、插件/MCP，并通过 experimental API 表达项目、队列、Remote Control、实时语音。对手机 MVP，优先封装这些已生成 schema 的 API 和双向事件。

桌面专有能力还经过 Electron IPC / worker 与 codex-app-tools NativePipe。例如窗口导航、打开面板、更新检查、managed worktree 恢复、Desktop terminal、local automation、特定文件 compiler/preview。这些不能仅靠 thread/start / turn/start 自动获得；第三方实现需要本机 companion bridge 或自行实现对应 UI/业务层。

官方 Remote Control 有现成 pairing 和设备管理接口，也有手机控制 PC 的 UI 文案；本机没有完成官方 relay、第三方 client enrollment、端到端授权与平台可用性验证，因此不能承诺任意自建手机应用可直接加入官方设备网络。

推荐层次：手机 UI ↔ 你的认证通信层 ↔ 本机 companion ↔ app-server；按需求再为 Desktop IPC/MCP 添加 adapter。单独启动一个 app-server 也不能默认等同“连接到当前桌面进程并继承全部窗口状态”。本机运行方式目前是 stdio。

## 10. 证据定位与交付文件

本机来源：

- `C:\Program Files\WindowsApps\OpenAI.Codex_26.1007.2314.0_x64__2p2nqsd0c76g0\app\resources\app.asar`：package metadata、Electron main/preload/worker、webview modules、native menus。
- ASAR 内 `.vite/build/main-BklS_2Y2.js` / `worker.js`：desktop handlers、NativePipe、automation、Git/worktree 与 compiler 接入。
- ASAR 内 `webview/assets/command-messages-945b39762771.js`：命令标签；`use-visible-settings-sections-a242a425fc16.js`：surface / auth / feature gate。
- ASAR 内 `remote-control-connections-visibility-2d7f31c9221e.js`：slingshotEnabled、available、accessRequired 控制；Browser extensions / locked CU 另有多重 gate。
- `C:\Program Files\WindowsApps\OpenAI.Codex_26.1007.2314.0_x64__2p2nqsd0c76g0\AppxManifest.xml`：Windows integrations。
- `C:\Users\xiaoyu\.codex\plugins\cache`：插件、skills、MCP server 注册。
- 本机 CLI help、features list、default / experimental schema；当前会话工具 metadata。

附带文件：

- [结构化功能清单](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/codex-feature-inventory.json)：分类、状态、flags、API、插件和工具目录。
- [完整 API CSV](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/codex-app-server-api.csv)：266 个消息 envelope 方法及参数字段。
- [完整 JSON Schema ZIP](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/codex-app-server-schemas.zip)：本机生成的 default 与 experimental schema。
- [本地证据索引](C:/Users/xiaoyu/Documents/Codex/2026-10-14/new-chat-2/outputs/codex-local-evidence.json)：UI 标签、来源文件/字符偏移、worker cases、插件方法。

没有附带原始 config.toml、账号凭据、cookie 或聊天历史。UI message extraction 与 switch-case 数量不用于“功能总数”：vendor、翻译、共享产品代码会显著放大数量。
