# MobileCodex

[中文 README](README.md) · [License](LICENSE) · [Roadmap](docs/development/roadmap.md)

MobileCodex is an experimental Windows Bridge and Android client that connects a phone to a running Codex Desktop instance so existing tasks can be viewed and continued remotely.

> The project is in early access. The Bridge and Android client are ready for development and testing, but compatibility depends on the Codex Desktop version. Please use Issues to report device differences, bugs, and improvement ideas.

## Logo call for contributions

We are looking for a simple, recognizable MobileCodex logo that works as an Android icon and on the project website. You can contribute in either of these ways:

- Open a [`Logo proposal` issue](https://github.com/awaxiaoyu/MobileCodex/issues) with SVG or PNG artwork, light/dark previews, and a short design note.
- Open a pull request with source files under `assets/branding/`, including the font, shape, and third-party asset license information.
- The proposal must be usable, modifiable, and redistributable under the Apache-2.0 project license. Do not include assets that cannot be relicensed for this use.

The community will discuss candidates before selection. Submitting a proposal gives the maintainers permission to show it in the repository, app, and project pages; final licensing details will be confirmed before a proposal is merged.

## Current capabilities

The public repository contains the Windows Bridge and Android Flutter client. The iOS client is currently outside the public source scope.

- Pairing, TLS certificate pinning, device revocation, and reconnect;
- Project and chat listing, reading, creation, and resume;
- Task submission, streamed responses, Plan/Default, model, and effort;
- Steer, Interrupt, user questions, and supported approval forms;
- Task diffs, scoped artifact downloads, and Android sharing;
- Bounded event cache, snapshots, request status, and capability checks.

The phone does not receive arbitrary shell, Terminal, filesystem, account configuration, raw IPC, or generic tool-call access. Commands and file operations remain authorized and executed by the Agent on the computer.

## Architecture

~~~mermaid
flowchart LR
    Android[Android Flutter client] <-->|authenticated WSS| Bridge[Windows Bridge]
    Bridge --> Adapter[Desktop adapters]
    Adapter --> Desktop[Codex Desktop]
    Desktop --> Agent[Agent tools and workspace]
~~~

The Bridge handles pairing, device permissions, version checks, request correlation, and event recovery. Desktop adapters register only the business actions needed by the phone; the phone never calls private Desktop APIs directly.

## Repository layout

~~~text
src/                    Bridge, WSS server, RPC, device, and policy code
adapters/               Desktop Main/Renderer adapters
native/                 NativePipe integration
schemas/                Native request/reply and Bridge schemas
schemas/bridge/         Public Bridge envelope, examples, and capability data
apps/android/           Flutter Android client
scripts/                Start, build, smoke-test, and benchmark scripts
tests/                  Node fixtures and Bridge tests
docs/development/       Verification, benchmark, and roadmap
docs/guides/            Desktop settings and usage guides
.github/workflows/      Android CI and Release
~~~

`dist/`, `.local/`, `node_modules/`, `apps/ios/`, `docs/design/`, and `docs/evidence/` are local or excluded content and should not be committed. Design Markdown is maintained only in local workspaces; the public protocol contract is the JSON under `schemas/bridge/`.

## Requirements

- Windows x64;
- Node.js 24 or newer;
- pnpm 11;
- Flutter 3.47.7 / Dart 3.13.5;
- JDK 17 for Android APK builds;
- A Codex Desktop version listed in `adapters/main/compatibility.json`;
- Frida 17.23.3 and OpenSSL when using the Frida-backed Bridge.

## Quick start

Install dependencies from the repository root:

~~~powershell
pnpm install --frozen-lockfile
~~~

Prepare the Frida runtime without committing runtimes, certificates, pairing JSON, or tokens:

~~~powershell
$env:MOBILE_CODEX_FRIDA_PYTHON = 'C:\path\to\python.exe'
& $env:MOBILE_CODEX_FRIDA_PYTHON -m pip install --target .local/frida frida==17.23.3
~~~

Start the Bridge for an already running Codex Desktop:

~~~powershell
powershell -NoProfile -File scripts/serve-desktop.ps1 -Address 192.0.2.10
~~~

Give the one-time pairing information printed by the script to the Android client. `-ReadOnly` disables control actions. The default WSS port is 37842; admin HTTP should listen only on loopback and must not be exposed to a LAN or the public internet.

## Android client

~~~powershell
cd apps/android
flutter pub get
flutter analyze
flutter test
flutter run
~~~

Build a debug APK:

~~~powershell
flutter build apk --debug
~~~

On first connection, paste pairing JSON or scan the QR code on the Android connection screen. Pairing tokens are stored in Android secure storage and the Bridge certificate fingerprint is pinned. See [apps/android/README.md](apps/android/README.md) for client details.

## Bridge commands

~~~powershell
pnpm typecheck
pnpm test
pnpm benchmark
pnpm smoke:frida
pnpm smoke:mobile
pnpm build:windows
~~~

Smoke commands require a compatible Desktop instance and are not offline unit tests. `pnpm benchmark` uses local fixtures by default and writes results to the ignored `.local/benchmarks/` directory.

## Protocol and security boundary

The envelope, examples, and capability scope are in [`schemas/bridge/`](schemas/bridge/). The Bridge validates:

- device token, TLS fingerprint, backend generation, and thread/turn ownership;
- the capability registry and method/field allowlists;
- task-scoped artifact references, rejecting arbitrary local paths;
- duplicate requests, stale generations, unknown mutations, and resolved approvals.

Codex credentials, project paths, and permission configuration on the computer are never sent to the phone. Treat `.local/`, certificates, pairing secrets, tokens, logs, and real task content as sensitive data.

## CI and automatic Releases

`.github/workflows/android.yml` runs Node typecheck/test, Flutter analyze/test, and a debug APK build on a GitHub-hosted Ubuntu runner. After a successful build on `main`, the workflow automatically creates a GitHub Release with the x86_64 debug APK attached. Release tags use `android-v<version>-<run id>` and are available on [Releases](https://github.com/awaxiaoyu/MobileCodex/releases).

## Documentation

- [Roadmap](docs/development/roadmap.md)
- [Development verification](docs/development/verification.md)
- [Performance benchmark](docs/development/benchmark.md)
- [Desktop settings guide](docs/guides/desktop-settings.md)
- [Public protocol schema](schemas/bridge/mobile-codex-bridge-v1.schema.json)
- [Protocol examples](schemas/bridge/mobile-codex-bridge-v1.examples.json)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

This project is licensed under the [Apache License 2.0](LICENSE). Third-party dependencies retain their respective licenses.
