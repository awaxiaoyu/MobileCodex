# Bridge 性能基准

基准入口是 `pnpm benchmark`，结果写入 `.local/benchmarks/benchmark-<timestamp>.json`。报告包含样本数、总耗时、p50/p95/p99、吞吐、Node 进程 CPU 时间和 CPU 百分比。

当前覆盖范围：

- `bridge.handle.fake-backend`：复用 `Bridge.handle` 的真实校验、去重和 backend 路由，backend 本身是进程内 fake，仅用于隔离 Bridge 控制面。
- `nativepipe.encode-decode`：复用 `encodeFrame` 和 `FrameDecoder`，测 framing/JSON Buffer 路径。
- `nativepipe.named-pipe-roundtrip`：在 Windows named pipe 上运行本地 echo fixture，包含 `NativePipeClient`、`JsonRpc` 和 framing；它不是 Codex Desktop 的真实 NativePipe。
- `wss.rpc-roundtrip`、`wss.event-throughput`：复用 TLS/WSS server、认证、JSON RPC 和事件广播，连接到本机回环 fixture。
- `frida.dispatch-rate-fixture`：按当前 Frida agent 的 120ms 最小调度间隔模拟 owner-thread 调度，不连接 Desktop。
- `frida.real-desktop-call`：默认标为 unavailable。设置 `MOBILE_CODEX_BENCH_FRIDA=1` 后，才会 attach 当前 Desktop 并测真实 `model/list` 调用；可用 `MOBILE_CODEX_BENCH_FRIDA_PID` 指定 PID。

可用环境变量：

```powershell
$env:MOBILE_CODEX_BENCH_ITERATIONS = '50000'
$env:MOBILE_CODEX_BENCH_FRAMES = '100000'
$env:MOBILE_CODEX_BENCH_WSS = '1000'
$env:MOBILE_CODEX_BENCH_FRIDA_ITERATIONS = '5'
node scripts/benchmark.ts
```

只有在相同机器、相同 Node/Codex 版本和相同样本参数下重复测量，才能比较迁移前后的变化。fixture 数据不能代替 Desktop 实测。只有当一个路径在重复报告中同时表现为明显的 CPU 或尾延迟热点，才进入 `bridge_core` 候选；迁移后必须保持 Node/TypeScript 控制面、Frida 注入和现有协议字节兼容。当前没有假定或创建可替换的 Bridge DLL。
