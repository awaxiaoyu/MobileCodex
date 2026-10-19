# MobileCodex

[English README](README.en.md) · [许可证](LICENSE) · [路线图](docs/development/roadmap.md)

MobileCodex 是一个实验性的 Windows Bridge 与 Android 客户端：将手机连接到正在运行的 Codex Desktop，让用户继续查看和操作已有任务。

> 项目仍处于 early access。Bridge 与 Android 客户端已经可以用于开发和测试，但兼容性取决于 Codex Desktop 版本；请把问题、设备差异和改进建议提交到 Issues。

## 项目 Logo 征集

我们正在为 MobileCodex 征集一个简洁、易识别、适合 Android 图标和网页展示的项目 Logo。欢迎提交设计方案：

- 在 [Issues](https://github.com/awaxiaoyu/MobileCodex/issues) 新建 `Logo proposal`，附上 SVG 或 PNG、浅色/深色背景预览和设计说明；
- 或提交 Pull Request，将源文件放在 `assets/branding/`，同时说明字体、图形和第三方素材的授权情况；
- 方案应允许项目在 Apache-2.0 条款下使用、修改和再发布，不要包含没有再授权权利的素材。

Logo 会由社区讨论后选定。提交方案即表示你允许项目维护者在仓库、应用和项目页面中展示候选方案；最终采用的授权细节会在合并前确认。

## 当前能力

公开仓库当前包含 Windows Bridge 和 Android Flutter 客户端。iOS 客户端暂不属于公开源码范围。

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
schemas/                原生请求/回复与 Bridge schema
schemas/bridge/         公开的 Bridge envelope、示例和能力范围数据
apps/android/           Flutter Android client
scripts/                启动、构建、smoke test 和 benchmark
tests/                  Node fixture 与 Bridge tests
docs/development/       验证、benchmark 和路线图
docs/guides/            Desktop 设置入口和运行指南
.github/workflows/      Android CI 与 Release
~~~

`dist/`、`.local/`、`node_modules/`、`apps/ios/`、`docs/design/` 和 `docs/evidence/` 都是本地或排除内容，不应提交。设计 Markdown 只在本地工作区维护；公开协议以 `schemas/bridge/` 中的 JSON 为准。

## 环境要求

- Windows x64；
- Node.js 24 或更高版本；
- pnpm 11；
- Flutter 3.47.7 / Dart 3.13.5；
- JDK 17（构建 Android APK）；
- 与 `adapters/main/compatibility.json` 匹配的 Codex Desktop；
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

将脚本输出的一次性 pairing 信息交给 Android 客户端。`-ReadOnly` 可以关闭控制动作。默认 WSS 端口为 37842，admin HTTP 只应监听本机回环地址；不要把 admin 端口暴露到 LAN 或公网。

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

smoke 命令需要正在运行的兼容 Desktop；它们不是离线单元测试。`pnpm benchmark` 默认使用本机 fixture，结果写入被忽略的 `.local/benchmarks/`。

## 协议与安全边界

协议 envelope、示例和能力范围位于 [`schemas/bridge/`](schemas/bridge/)。Bridge 会校验：

- 设备 token、TLS fingerprint、backend generation 和 thread/turn 归属；
- capability registry 与方法/字段 allowlist；
- task-scoped artifact 引用，拒绝任意本机路径；
- 重复请求、旧 generation、未知 mutation 和已经解决的审批。

电脑上的 Codex credentials、项目路径和权限配置不会发送给手机。请把 `.local/`、证书、pairing secret、token、日志和真实任务内容视为敏感数据。

## CI 与自动 Release

`.github/workflows/android.yml` 在 GitHub-hosted Ubuntu runner 上执行 Node typecheck/test、Flutter analyze/test 和 debug APK 构建。`main` 分支上的构建成功后，workflow 会自动创建 GitHub Release，并附带 x86_64 debug APK。Release tag 使用 `android-v<版本>-<run id>`，可从 [Releases](https://github.com/awaxiaoyu/MobileCodex/releases) 下载。

## 文档

- [路线图](docs/development/roadmap.md)
- [开发验证](docs/development/verification.md)
- [性能 benchmark](docs/development/benchmark.md)
- [Desktop 设置入口](docs/guides/desktop-settings.md)
- [公开协议 schema](schemas/bridge/mobile-codex-bridge-v1.schema.json)
- [协议消息示例](schemas/bridge/mobile-codex-bridge-v1.examples.json)
- [贡献指南](CONTRIBUTING.md)
- [安全报告](SECURITY.md)

## 许可证

本项目采用 [Apache License 2.0](LICENSE)。第三方依赖遵循各自的许可证。
