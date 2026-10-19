# Bridge 性能 benchmark

运行：

~~~powershell
pnpm benchmark
~~~

结果默认写入被 Git 忽略的 .local/benchmarks/benchmark-<timestamp>.json。报告包含样本数、总耗时、p50/p95/p99、吞吐和 Node CPU 时间。

## 覆盖路径

- Bridge.handle：真实校验、去重和 backend 路由，backend 使用进程内 fixture。
- NativePipe codec：frame 编解码和本机 named pipe echo fixture。
- WSS RPC：TLS、认证、RPC round-trip 和事件广播。
- Frida dispatch：owner-thread 调度 fixture；默认不连接 Desktop。
- Real Desktop：只有设置 MOBILE_CODEX_BENCH_FRIDA=1 才会 attach 当前 Desktop。

fixture 结果不能代替真实 Desktop 或实体手机数据。只有在相同机器、Node/Codex 版本和样本参数下重复测量，才可以比较改动前后性能。
