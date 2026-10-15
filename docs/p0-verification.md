# 验证记录

日期：2026-10-15（Asia/Singapore）。Desktop product `26.1007.21434` / build `13901`，CLI `0.162.0-alpha.17.2`，Node `24.19.0`，Frida `17.23.3`，Flutter `3.47.7` / Dart `3.13.5`。

本机注入观测到 Main runtime：node `24.19.0`、electron `155.0.8059.40`、chrome `155.0.8059.40`、v8 `15.5.35.20`。保留实机原值，不将其替换为此前静态包分析的 Electron 版本。

## 当前 Desktop 实机通过

- discovery 识别 Main 和原 app-server 子进程；PID 动态发现，未硬编码。
- Frida attach 运行中 Main，动态解析 `chrome.dll` N-API exports，验证 owner thread/current isolate 后执行；无需 CDP、重启或修改安装包。
- 持续 install/call/drain/shutdown JSONL 通道复用原 `electronBridge.sendMessageFromView`，模型列表返回 8 条、聊天列表返回 20 条，当前长聊天读取成功。
- 新建专用 Desktop 测试聊天；`gpt-6.1-sol` / `low` 发送成功，收到 agent delta。
- 同一个 turn 的 Steer、Interrupt 成功，收到 interrupted 通知，thread/read 确认 interrupted。
- 在同一个测试 thread resume 后启用 Plan，收到 `item/tool/requestUserInput`；Bridge 回复成功，重复回复拒绝，原 resolved 通知成功关联。
- 任务 snapshot 成功，审批列表为空；正在变化的任务曾返回 `snapshot.unstable`，等待后恢复，未伪造 cursor。
- 每次正常卸载均确认 `hooksRestored: true`；Desktop 保持运行，未改变原主机权限。
- WSS → Bridge → 原 Desktop：12 个项目、8 个模型、20 条聊天，snapshot/resume 成功；设备撤销关闭码 1008。

证据见 `docs/evidence/frida-shared-smoke.json`、`desktop-turn-smoke.json`、`desktop-plan-smoke.json`、`mobile-desktop-smoke.json`。只保留时间、关联 id、计数和验证状态，没有复制任务回答、配置或凭据。

此前 NativePipe 实测仍有效：43 项 catalog、12 项项目、list/read 成功。独立 app-server 的 initialize/model/list 通过，但不作为 Desktop live control 的依据。

## 传输与模拟测试通过

- `node --test tests/*.test.ts`：19 项通过。
- `tsc -p tsconfig.json`：strict 类型检查通过。
- Main 审批仲裁：两次竞争回复只调用原 handler 一次，保持 this/Promise/异常；失败保持 unknown。
- Renderer 的 start/chunk/end token 流还原，逐序列 ACK，卸载、版本拒绝通过。
- mutation id 合并、generation、字段/方法限制、有界事件缓存、稳定/不稳定 snapshot 通过。
- artifact 注册限于任务回答明确引用的 workspace 文件；跨任务/任意路径拒绝。
- 真正的本机 HTTPS/WSS：拒绝未配对、配对只使用一次、认证 RPC、撤销关闭连接通过。
- Flutter 与 Node Bridge 的真实本机连接：错误证书 pin 被拒绝，正确 pin 配对、WSS RPC、撤销处理通过。任务 backend 在此测试中是空 registry；不等同实体手机实测。
- Flutter widget 测试通过；Flutter analyze 无问题；Android assets bundle 编译成功。

## 尚未验收

- 实体 Android/iPhone 的完整使用、锁屏后台恢复、LAN/VPN 连接。
- 真实 command/file/permission/MCP 请求各一个用例；真实电脑 UI 与手机同时点击竞争。当前真实仲裁只覆盖用户问题回复，竞态使用 mock handler 验证。
- chunked 还原已测试及长 thread/read 实机通过，但该次长读取是否实际走 chunked 未做独立计数证明。
- 真实任务生成的附件通过实体手机预览/分享；当前 file scoping 测试使用本机 fixture。
- 大量输出和网络断开后的手机恢复。snapshot/事件缓存逻辑与客户端实现存在，尚未进行实体手机故障注入验收。
- Android APK：已尝试，本机 JDK 21/Android SDK 36 可用，但 Gradle distribution 重定向 GitHub 时网络超时；没有 APK。iOS 未在 Windows 构建。
- 独立 DLL/Windows native loader、installer/service、自动启动、多版本兼容；当前交付是 Frida helper 路线。

不把“函数存在”“模拟通过”“当前 Desktop 实测”“实体手机验收”混为同一种状态。
