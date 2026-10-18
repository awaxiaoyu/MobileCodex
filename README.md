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
pnpm install --frozen-lockfile
$env:MOBILE_CODEX_FRIDA_PYTHON = 'C:\path\to\WindowsPython\python.exe'
& $env:MOBILE_CODEX_FRIDA_PYTHON -m pip install --target .local/frida frida==17.23.3
```

打开已有 Codex Desktop，再运行：

```powershell
# 手机与电脑在同一 LAN 或已有 VPN。替换为手机可达的电脑地址。
powershell -NoProfile -File scripts/serve-desktop.ps1 -Address 192.168.1.10
```

脚本创建 Bridge 自有 TLS identity、attach 当前 Desktop，并将 2 分钟有效的一次性配对信息写到 `.local/pairing.json`。在 Codex 设置菜单打开 Bridge，点击“生成一次性配对二维码”后可直接用手机扫描，也可以在手机点击“连接电脑”粘贴 pairing JSON。配对后的 token 放手机 OS secure storage；电脑只持久化 token hash。配对信息和本机 admin token 不打印到启动日志。

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

撤销立即关闭该设备的 WSS，后续认证失败。设备的信任记录保存在 `%LOCALAPPDATA%\\MobileCodexBridge\\.local\\devices.json`，只保存 token hash；手机端 token 保存在 OS secure storage，应用重启会自动恢复并重连，不需要再次扫码。电脑自有凭据、Codex token/config 不传给手机。

### 非局域网连接

WSS 本身可以使用公网地址，但必须有网络路径把手机连接转发到 Bridge 的 `mobile-port`。推荐使用 Tailscale/ZeroTier 等 VPN：让手机和电脑加入同一虚拟网络，启动时把 pairing URL 设置为 VPN 地址。也可以使用路由器端口转发、DDNS 和 TLS passthrough：

```powershell
$env:MOBILE_CODEX_PUBLIC_URL = 'wss://codex.example.com/ws'
.\dist\MobileCodexBridge\MobileCodexBridge.exe
# 或：Start-MobileCodexBridge.ps1 -Address 0.0.0.0 -PublicUrl 'wss://codex.example.com/ws'
```

公网入口必须只转发 WSS `37842`，不能转发本机 admin HTTP `37841`。TLS passthrough 要保持 Bridge 证书不变，这样手机的 fingerprint pin 才能继续工作。当前仓库没有托管 relay；如果不想开放端口，需要部署 relay 或 VPN 服务后把它的可达地址填入 `MOBILE_CODEX_PUBLIC_URL`。

## 功能与协议

`desktop-shared` 是 Frida 或 CDP adapter 复用的当前 Desktop connection；`desktop-tools` 是有限 NativePipe 工具；`companion-standalone` 是另启 app-server 的开发模式。它们在 backend kind 中明确区分。

### Desktop 设置中的 Bridge

使用 `--frida` 启动时，adapter 会把一个短期、仅回环可用的 UI session 传给当前 renderer。对于已识别的 Desktop `26.1007.21434` 账户/齿轮弹出菜单，它会在“设置”和“帮助”之间插入 `Mobile Codex` 菜单项并打开管理面板；面板通过本机 `/ui/status` 读取真实 backend、generation、WSS、Frida、hooks、事件缓存、设备和环境检查状态。一次性 pairing、设备撤销也只通过该 session 转发，手机 token、Codex token、密码和私钥不会进入 renderer 或日志。

设置菜单和 React 私有组件没有稳定公开 API。adapter 因此先做 UA/build 与 DOM capability 检查，不能识别时不注入，并返回可读的失败原因；已注入页面由 MutationObserver 维持入口，卸载时恢复原菜单和 hooks。Mobile Codex 面板使用中文显示运行状态、配对设备、二维码、参数、功能开关状态和环境检测，并用绿色/黄色/红色区分通过、警告和失败。事件流可以直接实时切换；控制模式和审批转发只有 Bridge 启动时带 `--allow-control` 才可切换，否则显示启动参数提示。WSS、hooks 等启动或生命周期能力只读显示并标明是否需要重启。

这部分没有引入 DLL。C++ 只在 benchmark 证明某个 IPC/序列化热点后才考虑，以稳定 C ABI/IPC 连接现有 Node/TypeScript 控制面；Frida 注入和版本拒绝仍由现有 helper 负责。

手机选择 backendId/generation 和 threadId。请求包含唯一 id；未知 mutation 不自动重发，可通过 `bridge.request.get` 查询。`bridge.events.resume` 重放缓存；`bridge.snapshot.get` 返回带 cursor 的稳定任务状态，读取期间有该任务事件时重试，无法稳定时返回 `snapshot.unstable`。

网络不能传任意 JavaScript、函数名、IPC channel、shell、文件路径或 tools/call。`codex.request` 同样受白名单限制。model/effort 只能选当前 Desktop catalog；手机不能传 developer instructions 或覆盖 cwd/roots/sandbox/approval/provider。

项目与聊天 sidebar 优先合并当前 Codex NativePipe 数据，并从 `~/.codex/state_*.sqlite` 只读补充项目根目录、线程项目归属和置顶状态；可用 `MOBILE_CODEX_STATE_DB` 指定状态库路径。无法读取状态库时提供配置的 workspace。新建聊天的路径由电脑按项目映射，手机只提交 projectId。首版附件只接受配置 workspace 内、Agent 回答明确链接的文件；不提供任意路径下载。

Desktop 与手机通过 Main 原 IPC handler 的同步 claim 共用一次审批回复。提交失败标为 unknown，原始 Promise/异常语义保留；Main/Renderer hooks 可卸载。helper 退出或失联后 Main watchdog 自动清理。这个实现是 Frida helper + 进程内 JavaScript adapter，并非独立 DLL 成品。

## 开发验证

```powershell
pnpm typecheck
pnpm test
pnpm benchmark
node scripts/smoke-frida.ts
# 以下两个脚本会创建/使用专用 Desktop 测试聊天并消耗模型额度。
node scripts/smoke-turn.ts
node scripts/smoke-plan.ts
.local/flutter/bin/flutter.bat analyze --no-pub apps/mobile
```

`pnpm benchmark` 会将 Bridge、NativePipe、WSS 和 Frida 调度的样本、p50/p95/p99、吞吐和 Node CPU 时间写入 `.local/benchmarks/`。NativePipe/WSS 默认使用本机 fixture；Frida 只有设置 `MOBILE_CODEX_BENCH_FRIDA=1` 才会连接运行中的 Desktop。迁移到 C++ `bridge_core` 前应先取得真实 Desktop 数据并重复确认热点，当前仓库没有可替换的 Bridge DLL。

## Windows portable EXE

在 Windows 上运行 `pnpm build:windows` 会生成 `dist/MobileCodexBridge/MobileCodexBridge.exe`。这是一个可双击启动的 portable 包：Node/TypeScript 控制面内嵌在 EXE，`app/` 中保留 Frida adapter、schemas，`runtime/` 中包含 Python 和 Frida native package。证书、设备记录和本地 token 写入 `%LOCALAPPDATA%\\MobileCodexBridge\\.local`，不会写入发布目录。首次构建会复制约 700 MB 的 Python/Frida runtime；可用 `-SkipPythonRuntime` 生成不含运行时的轻量包，但启动前必须设置 `MOBILE_CODEX_FRIDA_PYTHON` 和 `MOBILE_CODEX_FRIDA_DEPS`。

```powershell
pnpm build:windows
powershell -NoProfile -File dist/MobileCodexBridge/Start-MobileCodexBridge.ps1 -Address 192.168.1.10
```

`Start-MobileCodexBridge.ps1` 会生成或复用 `%LOCALAPPDATA%\\MobileCodexBridge\\.local\\tls` 中的证书，并启动带 Frida、WSS 和控制权限的 Bridge；使用 `-ReadOnly` 可禁用控制权限。也可以直接运行 `MobileCodexBridge.exe` 并自行传递 `serve` 参数。

直接双击 `MobileCodexBridge.exe` 时会自动生成或复用 TLS 证书，并默认执行 `serve --frida --allow-control`、WSS `0.0.0.0:37842` 和一次性 pairing URL。它会优先选择 Windows DHCP 局域网 IPv4 作为手机连接地址；可用 `MOBILE_CODEX_PAIR_ADDRESS`、`MOBILE_CODEX_MOBILE_PORT` 或 `MOBILE_CODEX_MOBILE_BIND` 覆盖。首次生成证书需要 `openssl.exe`，也可用 `MOBILE_CODEX_OPENSSL` 指定路径。需要固定地址和端口时使用上面的启动脚本。

EXE 仍需本机安装并运行兼容版本的 Codex Desktop；当前 Frida adapter 只接受已验证的 Desktop `26.1007.21434` runtime。该打包方式不会替换或修改 Codex 安装，也没有把 Codex token、密码或私钥打进 EXE。

Flutter 在 `apps/mobile` 下运行 `flutter test`、`flutter build bundle --target-platform android-arm64`、`flutter build apk --debug`。本机 Gradle distribution 下载曾超时，Android APK 已改由 GitHub Actions 成功打包；iOS 需要 macOS/Xcode 构建。

### GitHub Actions Android 构建

仓库的 `Android APK` workflow 使用 GitHub-hosted Ubuntu runner，依次执行 Node bridge 的 typecheck/test、Flutter analyze/test，并上传 `mobile-codex-debug-apk` artifact（保留 14 天）。推送到 `main`（涉及 Bridge 或 Android 文件时）会自动构建，也可以在 GitHub Actions 页面用 `Run workflow` 手动触发。APK 输出路径为 `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`。

[首次成功构建](https://github.com/awaxiaoyu/MobileCodex/actions/runs/38661032222) 用时 8 分 55 秒。下载后的本地 APK 在 `.local/artifacts/android-debug/app-debug.apk`；artifact 校验和见 [构建记录](docs/evidence/android-ci-build.json)。这是 debug 签名的测试安装包，尚未完成实体手机验收。

### GitHub Actions iOS 构建

`.github/workflows/ios.yml` 使用 GitHub-hosted `macos-15` runner，依次执行 Node bridge 的 typecheck/test、Flutter analyze/test，并运行 `flutter build ipa --release --no-codesign`。推送到 `main`（涉及 Bridge 或 iOS 文件时）会自动构建，也可以在 GitHub Actions 页面用 `Run workflow` 手动触发。构建会上传 `mobile-codex-ios-unsigned-ipa` 和 `mobile-codex-ios-xcarchive` 两个 artifact，各保留 14 天。

当前仓库没有 Apple Distribution certificate 或 provisioning profile，因此 IPA 是 unsigned，不能直接安装到真机或提交 App Store；需要发布签名时，在 workflow 中增加 Apple signing secrets 和 export options。

- [实测记录](docs/p0-verification.md)
- [后续验收](docs/NEXT.md)
- [手机功能范围](docs/design/Mobile-Codex-手机功能范围.md)
- [协议设计](docs/design/Mobile-Codex-Bridge-协议设计.md)

设计目录保留此前范围文档；当前实现和限制以此 README 与实测记录为准。
