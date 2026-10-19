# MobileCodex

MobileCodex 是一个实验性的 Windows Bridge 与 Android 客户端：把手机连接到正在运行的 Codex Desktop，让用户继续查看和操作已有任务。

公开仓库当前只包含 Windows Bridge 和 Android Flutter 客户端。iOS 客户端暂不属于公开源码范围；本机已有的 iOS 文件会被 Git 忽略，不会进入后续公开提交。

## 项目状态

项目仍处于 early access 阶段。Bridge、配对、WSS RPC、聊天任务和 Android UI 已有实现与自动化测试，但兼容性取决于本机 Codex Desktop 版本，实体设备、断线恢复和复杂审批场景仍需要使用者自行验收。

当前首版支持：

- 配对、TLS certificate pinning、设备撤销和重连；
- 项目与聊天列表、读取、新建和恢复；
- 发送任务、流式回答、Plan/Default、model/effort；
- Steer、Interrupt、用户问题和支持的审批表单；
- 任务 diff、明确关联的附件下载与 Android 分享；
- 有界事件缓存、snapshot、请求状态查询和版本 capability 检查。

手机不会获得任意 shell、Terminal、文件系统、账号配置、原始 IPC 或通用 tool call。命令和文件操作仍由电脑上的 Agent 按原有权限执行。

## 架构

~~~mermaid
flowchart LR
    Android[Android Flutter client] <-->|authenticated WSS| Bridge[Windows Bridge]
    Bridge --> Adapter[Desktop adapters]
    Adapter --> Desktop[Codex Desktop]
    Desktop --> Agent[Agent tools and workspace]
~~~

Bridge 负责配对、设备权限、版本检查、请求关联和事件恢复。Desktop adapter 只注册手机需要的业务动作；手机不直接访问 Desktop 的私有 API。

## 目录

~~~text
src/                    Bridge、WSS server、RPC、设备和策略
adapters/               Desktop Main/Renderer adapter
native/                 NativePipe 相关代码
schemas/                原生请求和回复 schema
apps/android/           Flutter Android client
scripts/                启动、构建、smoke test 和 benchmark
tests/                  Node fixture 与 Bridge tests
docs/design/            产品范围、协议和 UI 设计
docs/development/       验证、benchmark 和 roadmap
docs/guides/            Desktop 设置入口和运行指南
.github/workflows/      Android CI
~~~

dist/、.local/、node_modules/、apps/ios/ 和 docs/evidence/ 都是本地或排除内容，不应提交。

## 环境要求

- Windows x64；
- Node.js 24 或更高版本；
- pnpm 11；
- Flutter 3.47.7 / Dart 3.13.5；
- JDK 17（构建 Android APK）；
- 与 adapters/main/compatibility.json 匹配的 Codex Desktop；
- Frida 17.23.3 和 OpenSSL（Bridge 使用 Frida 时）。

## 快速开始

在仓库根目录安装依赖：

~~~powershell
pnpm install --frozen-lockfile
~~~

准备 Frida 运行时。不要把运行时、证书、pairing JSON 或 token 写入 Git：

~~~powershell
$env:MOBILE_CODEX_FRIDA_PYTHON = 'C:\path\to\python.exe'
& $env:MOBILE_CODEX_FRIDA_PYTHON -m pip install --target .local/frida frida==17.23.3
~~~

启动已经打开的 Codex Desktop 对应 Bridge：

~~~powershell
powershell -NoProfile -File scripts/serve-desktop.ps1 -Address 192.0.2.10
~~~

将脚本输出的一次性 pairing 信息交给 Android 客户端。-ReadOnly 可以关闭控制动作。默认 WSS 端口为 37842，admin HTTP 只应监听本机回环地址；不要把 admin 端口暴露到 LAN 或公网。

## Android 客户端

~~~powershell
cd apps/android
flutter pub get
flutter analyze
flutter test
flutter run
~~~

构建 debug APK：

~~~powershell
flutter build apk --debug
~~~

首次连接时，在 Android 应用的连接页面粘贴 pairing JSON 或扫描二维码。配对 token 使用 Android secure storage 保存，证书 fingerprint 用于 TLS pinning。更详细的客户端说明见 [apps/android/README.md](apps/android/README.md)。

## Bridge 命令

~~~powershell
pnpm typecheck
pnpm test
pnpm benchmark
pnpm smoke:frida
pnpm smoke:mobile
pnpm build:windows
~~~

smoke:frida 和 smoke:desktop 需要正在运行的兼容 Desktop；它们不是离线单元测试。pnpm benchmark 默认使用本机 fixture，结果写入被忽略的 .local/benchmarks/。

## 协议与安全边界

协议 envelope 和示例位于 [mobile-codex-bridge-v1.schema.json](docs/design/mobile-codex-bridge-v1.schema.json) 与 [mobile-codex-bridge-v1.examples.json](docs/design/mobile-codex-bridge-v1.examples.json)。Bridge 会校验：

- 设备 token、TLS fingerprint、backend generation 和 thread/turn 归属；
- capability registry 与方法/字段 allowlist；
- task-scoped artifact 引用，拒绝任意本机路径；
- 重复请求、旧 generation、未知 mutation 和已经解决的审批。

电脑上的 Codex credentials、项目路径和权限配置不会发送给手机。请把 .local/、证书、pairing secret、token、日志和真实任务内容视为敏感数据。

## CI

.github/workflows/android.yml 在 GitHub-hosted Ubuntu runner 上执行 Node typecheck/test、Flutter analyze/test 和 debug APK 构建，并上传 x86_64 APK artifact。workflow 不包含 iOS job。

## 文档

- [产品和开发范围](docs/design/app-plan.md)
- [手机能力边界](docs/design/mobile-capability-scope.md)
- [Bridge 协议](docs/design/bridge-protocol.md)
- [Android UI 设计](docs/design/ui-design.md)
- [开发验证](docs/development/verification.md)
- [性能 benchmark](docs/development/benchmark.md)
- [路线图](docs/development/roadmap.md)
- [Desktop 设置入口](docs/guides/desktop-settings.md)
- [贡献指南](CONTRIBUTING.md)
- [安全报告](SECURITY.md)

## 许可证

本项目采用 [Apache License 2.0](LICENSE)。第三方依赖遵循各自的许可证。
