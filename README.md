# MobileCodex

通过 Windows Bridge，在手机上继续当前 Codex Desktop 的聊天与任务。已经实现无需 CDP、无需重启的持续 Frida injection，以及 Flutter Android/iOS 客户端第一版。

## 当前状态

| 能力 | 验证 |
|---|---|
| 动态 attach Main → 原 JS 线程 → Renderer → 原 Desktop IPC | 当前 Codex 实机通过 |
| 模型/聊天列表、长聊天读取 | 实机通过，8 个模型、20 条聊天 |
| 新建聊天、发送、流式输出、model/effort | 专用 Desktop 测试聊天实机通过 |
| Steer / Interrupt / Plan | 同一 Desktop thread 实机通过 |
| 用户问题回复、重复回复拒绝、resolved、snapshot | 实机通过 |
| command/file/permission/MCP 请求及审批仲裁 | 已实现；通用仲裁模拟测试通过，真实验收目前覆盖用户问题 |
| 配对、认证 WSS、证书 pinning、撤销 | Node/Dart 真实本机传输测试通过 |
| 有界事件缓存、重连、任务附件引用与下载 | 实现完成，核心模拟测试通过；真实手机断线/下载待验收 |
| Flutter 聊天/项目选择、model/effort/Plan、问题/审批、Diff/附件分享 | analyze、widget/连接测试及 Android assets bundle 编译通过 |
| Android APK | GitHub Actions Ubuntu runner 构建通过，debug APK 已下载；实体手机待验收 |

Terminal、通用文件系统、IDE、Worktree/Git 管理器、Browser 控制、Desktop 布局仍按范围裁剪留在电脑。手机发送任务时，Agent 继续使用电脑原工具和权限。

## 环境

- Node 24；Windows x64。
- Windows Python 与 Frida `17.23.3`。本机已使用 Codex bundled Python 3.12 验证；MSYS2 Python 3.14 无法加载该 Frida wheel。
- Flutter `3.47.7` / Dart `3.13.5`。本机 SDK 在 `.local/flutter`，不修改全局 PATH。
- 支持 Codex Desktop `26.1007.21434`。私有运行时及 ABI 锁在 `adapters/main/compatibility.json`；未知版本拒绝安装 hooks。

Bridge 只有一个 runtime npm dependency：`ws`。它提供成熟的 WebSocket framing；TypeScript 和类型包仅用于开发检查。Flutter 使用 secure storage、crypto、Markdown 和原生附件分享依赖，版本见 lock file。

## 启动

本机 `.local/frida` 已准备好。从干净 checkout 安装时：

```powershell
npm ci
$env:MOBILE_CODEX_FRIDA_PYTHON = 'C:\path\to\WindowsPython\python.exe'
& $env:MOBILE_CODEX_FRIDA_PYTHON -m pip install --target .local/frida frida==17.23.3
```

打开已有 Codex Desktop，再运行：

```powershell
# 手机与电脑在同一 LAN 或已有 VPN。替换为手机可达的电脑地址。
powershell -NoProfile -File scripts/serve-desktop.ps1 -Address 192.168.1.10
```

脚本创建 Bridge 自有 TLS identity、attach 当前 Desktop，并将 2 分钟有效的一次性配对信息写到 `.local/pairing.json`。在手机点击“连接电脑”，粘贴此 JSON。配对后的 token 放手机 OS secure storage；电脑只持久化 token hash。配对信息和本机 admin token 不打印到启动日志。

`-ReadOnly` 启动只读模式。无需启动第二个 app-server，不改 Codex 安装包，不打开 CDP，也不改变原 sandbox/approval 配置。

底层 CLI：

```powershell
$env:MOBILE_CODEX_FRIDA_DEPS = "$PWD\.local\frida"
node src/cli.ts serve --frida --allow-control --tls-cert .local/tls/cert.pem --tls-key .local/tls/key.pem --pair-url wss://192.168.1.10:37842/ws
```

手机 WSS 默认端口 `37842`；本机 admin HTTP 只监听 `127.0.0.1:37841`。LAN 防火墙规则由部署时配置；本实现没有改系统防火墙或开机启动。

## 配对与撤销

从电脑本机使用 `.local/local-token` 访问 admin HTTP：

```powershell
$headers = @{ Authorization = 'Bearer ' + (Get-Content .local/local-token -Raw) }
Invoke-RestMethod http://127.0.0.1:37841/devices -Headers $headers
# 新的一次性配对 secret；结合原 WSS URL 和证书 fingerprint 生成新配对信息。
Invoke-RestMethod http://127.0.0.1:37841/pairing -Method Post -Headers $headers
$body = @{ deviceId = 'DEVICE_ID' } | ConvertTo-Json
Invoke-RestMethod http://127.0.0.1:37841/devices/revoke -Method Post -Headers $headers -ContentType application/json -Body $body
```

撤销立即关闭该设备的 WSS，后续认证失败。电脑自有凭据、Codex token/config 不传给手机。

## 功能与协议

`desktop-shared` 是 Frida 或 CDP adapter 复用的当前 Desktop connection；`desktop-tools` 是有限 NativePipe 工具；`companion-standalone` 是另启 app-server 的开发模式。它们在 backend kind 中明确区分。

手机选择 backendId/generation 和 threadId。请求包含唯一 id；未知 mutation 不自动重发，可通过 `bridge.request.get` 查询。`bridge.events.resume` 重放缓存；`bridge.snapshot.get` 返回带 cursor 的稳定任务状态，读取期间有该任务事件时重试，无法稳定时返回 `snapshot.unstable`。

网络不能传任意 JavaScript、函数名、IPC channel、shell、文件路径或 tools/call。`codex.request` 同样受白名单限制。model/effort 只能选当前 Desktop catalog；手机不能传 developer instructions 或覆盖 cwd/roots/sandbox/approval/provider。

项目列表优先来自当前 Codex 提供的 NativePipe；普通终端没有该上下文时提供配置的 workspace。新建聊天的路径由电脑按项目映射，手机只提交 projectId。首版附件只接受配置 workspace 内、Agent 回答明确链接的文件；不提供任意路径下载。

Desktop 与手机通过 Main 原 IPC handler 的同步 claim 共用一次审批回复。提交失败标为 unknown，原始 Promise/异常语义保留；Main/Renderer hooks 可卸载。helper 退出或失联后 Main watchdog 自动清理。这个实现是 Frida helper + 进程内 JavaScript adapter，并非独立 DLL 成品。

## 开发验证

```powershell
npm run typecheck
npm test
node scripts/smoke-frida.ts
# 以下两个脚本会创建/使用专用 Desktop 测试聊天并消耗模型额度。
node scripts/smoke-turn.ts
node scripts/smoke-plan.ts
.local/flutter/bin/flutter.bat analyze --no-pub apps/mobile
```

Flutter 在 `apps/mobile` 下运行 `flutter test`、`flutter build bundle --target-platform android-arm64`、`flutter build apk --debug`。本机 Gradle distribution 下载曾超时，Android APK 已改由 GitHub Actions 成功打包；iOS 需要 macOS/Xcode 构建。

### GitHub Actions Android 构建

仓库的 `Android APK` workflow 使用 GitHub-hosted Ubuntu runner，依次执行 Node bridge 的 typecheck/test、Flutter analyze/test，并上传 `mobile-codex-debug-apk` artifact（保留 14 天）。推送到 `main`（涉及 Bridge 或 Android 文件时）会自动构建，也可以在 GitHub Actions 页面用 `Run workflow` 手动触发。APK 输出路径为 `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`。

[首次成功构建](https://github.com/awaxiaoyu/MobileCodex/actions/runs/38661032222) 用时 8 分 55 秒。下载后的本地 APK 在 `.local/artifacts/android-debug/app-debug.apk`；artifact 校验和见 [构建记录](docs/evidence/android-ci-build.json)。这是 debug 签名的测试安装包，尚未完成实体手机验收。

- [实测记录](docs/p0-verification.md)
- [后续验收](docs/NEXT.md)
- [手机功能范围](docs/design/Mobile-Codex-手机功能范围.md)
- [协议设计](docs/design/Mobile-Codex-Bridge-协议设计.md)

设计目录保留此前范围文档；当前实现和限制以此 README 与实测记录为准。
