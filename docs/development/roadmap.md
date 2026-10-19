# 路线图

MobileCodex 的路线图按交付阶段维护。每一项进入下一阶段前，都需要有对应的实现、文档和验证记录；未经真实 Desktop 或设备验证的能力不会被当作已交付功能。

## 已完成：公开仓库基础

- [x] 发布 Windows Bridge 与 Android 客户端的公开边界说明。
- [x] 使用 Apache-2.0 许可证，补充贡献指南和安全报告入口。
- [x] 将 Bridge envelope、示例和能力范围整理为可机器读取的 JSON 资源。
- [x] 从公开树移除 iOS 工程、机器证据和本地设计 Markdown。
- [x] 建立 Node 与 Flutter 的离线检查，并在 `main` 构建成功后自动发布 Android Release。

## 当前阶段：稳定性与可复现安装

- [ ] 在真实 Android 设备上复核配对、证书 pinning、撤销、重连、锁屏恢复和 VPN。
- [ ] 建立 Codex Desktop compatibility matrix，明确支持、已知问题和安全拒绝版本。
- [ ] 固化 Bridge 与 Android 的版本兼容规则，让不匹配的客户端得到可读提示。
- [ ] 为长输出、断网、Bridge 重启、事件缓存缺失和 snapshot 恢复补充可重复 fixture。
- [ ] 为自动 Release 增加 APK 校验和、构建元数据与变更说明。

## 下一阶段：聊天体验

- [ ] 完善聊天历史的搜索、改名、归档、置顶和已读状态，并保持 Bridge allowlist 边界。
- [ ] 优化流式回答、Plan/Default、model/effort、审批和用户问题在小屏上的状态表达。
- [ ] 增加任务 diff、结果附件和 Android 分享的错误恢复与大小限制提示。
- [ ] 补齐 Talk/Steer/Interrupt、网络切换和后台恢复的无障碍与触控验收。
- [ ] 根据社区 Logo 征集结果确定品牌资产，并提供浅色/深色应用图标。

## 后续阶段：可维护的 Bridge 能力

- [ ] 将 capability registry、请求状态和事件恢复的诊断信息做成可读的开发模式页面。
- [ ] 为配对、撤销、证书轮换和只读模式提供端到端测试夹具。
- [ ] 评估任务队列、Goal 查看/编辑和通知；每项能力先完成协议与权限审查。
- [ ] 评估更多受限的附件类型与结果预览，不开放任意路径或通用文件 API。
- [ ] 提供稳定的本地开发脚本和最小示例，降低第三方 adapter 的上手成本。

## 社区与发布

- [ ] 建立 issue / pull request 模板，要求说明复现环境、Desktop 版本、设备和验证命令。
- [ ] 收集 Logo、翻译、设备兼容性和文档改进贡献。
- [ ] 为每次 Android Release 生成简短变更说明，保留可下载的构建产物。
- [ ] 在实现稳定后再讨论 beta / stable 版本策略，不提前承诺发布日期。

## 明确不在当前路线

Terminal、通用文件管理、任意路径读写、Desktop 窗口控制、账号配置、官方 relay、完整 MCP 管理、远程桌面、原始私有 IPC、通用 tool call 和 iOS 客户端不属于当前公开交付目标。手机端的命令和文件操作仍通过电脑上的 Agent 按原有权限执行。

## 路线图变更规则

路线图是公开承诺的优先级，不是所有 Codex Desktop 能力的镜像。新增项目必须说明用户价值、Bridge 方法与权限边界、兼容性影响、失败恢复方式和验证计划；无法验证的私有 API 只记录为待评估项。
