# Desktop Bridge 设置页

## 启动

```powershell
powershell -NoProfile -File scripts/serve-desktop.ps1 -Address 192.168.1.10
```

打开兼容版本的 Codex Desktop 后，Bridge adapter 会在左下角账户/齿轮按钮打开的弹出菜单中尝试添加 `Mobile Codex`，位置在“设置”和“帮助”之间。入口只有在 UA/build 和菜单标签 capability 同时匹配时才显示；菜单尚未打开时 adapter 会等待，不能匹配时安全降级，不修改原设置页面。

## 面板数据边界

- pairing 只返回一次性 `id`、`secret`、WSS URL 和证书 fingerprint；Bridge 同时生成一个本地 QR Data URL，二维码内容就是手机现有连接流程接受的 pairing JSON。设备 token 只保存在手机 secure storage，电脑只保存 hash。
- `/ui/status` 仅监听 `127.0.0.1`，使用独立短期 session header，不能替代 admin bearer，也不能用于手机 WSS。
- 状态来自 Bridge、backend、Frida helper、WSS 和事件缓存的运行数据，不使用本地假开关。
- Mobile Codex 设置页提供中文运行状态、语义颜色（PASS 绿色、WARN 黄色、FAIL 红色）和功能开关状态。事件流可以直接实时切换；控制模式和审批转发只有 Bridge 启动时带 `--allow-control` 才可切换，未带该参数时会显示原因。WSS、hooks 等启动或生命周期能力只读展示。
- 参数目前是启动时参数。UI 显示当前有效值和重启提示；没有经过验证的热更新不会被暴露。

## 设备信任与公网连接

Bridge 将已配对设备写入 `%LOCALAPPDATA%\\MobileCodexBridge\\.local\\devices.json`，只保存 token hash。手机 token 保存在 OS secure storage，应用启动会自动重连；设置面板显示信任设备、在线状态、最近连接时间，并支持撤销。撤销会立即关闭该设备的 WSS。

非局域网连接需要 VPN、端口转发或 relay 提供网络路径。可通过 `--public-url wss://host/ws`、`MOBILE_CODEX_PUBLIC_URL` 或 `Start-MobileCodexBridge.ps1 -PublicUrl` 把 pairing URL 指向公网入口；公网入口只转发 WSS 端口，不转发 `127.0.0.1:37841` admin HTTP。使用端到端 TLS passthrough，保持 Bridge 证书 fingerprint 不变；当前仓库不托管 relay 服务。

## 版本兼容

当前 renderer capability 锁定 `26.1007.21434`。Codex Desktop 私有 React registry、组件名和 route 都可能改变，未知版本必须先更新 capability 检查和 adapter 测试，再允许注入。

## Windows EXE

运行 `pnpm build:windows` 可生成 `dist/MobileCodexBridge/` portable 包。`MobileCodexBridge.exe` 是启动入口，`Start-MobileCodexBridge.ps1` 提供带 WSS/Frida 的标准启动参数，`app/` 保存 adapter/schema，`runtime/` 保存 Python/Frida。证书和设备数据存放在 `%LOCALAPPDATA%\\MobileCodexBridge\\.local`。`-SkipPythonRuntime` 只适用于已经配置 `MOBILE_CODEX_FRIDA_PYTHON` 与 `MOBILE_CODEX_FRIDA_DEPS` 的机器。

直接运行 EXE（无参数）会自动生成或复用 TLS 证书，启动 `serve --frida --allow-control` 和默认 WSS `0.0.0.0:37842`，并优先使用 Windows DHCP 局域网 IPv4 生成 pairing URL。`MOBILE_CODEX_PAIR_ADDRESS`、`MOBILE_CODEX_MOBILE_PORT` 和 `MOBILE_CODEX_MOBILE_BIND` 可覆盖自动值；首次生成证书需要 `openssl.exe`，可用 `MOBILE_CODEX_OPENSSL` 指定路径；需要固定地址时使用 `Start-MobileCodexBridge.ps1`。
