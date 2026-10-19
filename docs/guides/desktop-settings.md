# Desktop Bridge 设置入口

## 启动

在已打开 Codex Desktop 的 Windows 电脑上运行：

~~~powershell
powershell -NoProfile -File scripts/serve-desktop.ps1 -Address 192.0.2.10
~~~

Address 应替换成手机可以访问的 LAN 或 VPN 地址。使用 ReadOnly 参数可以关闭控制动作。

兼容版本通过 adapters/main/compatibility.json 检查。版本不匹配时 adapter 应拒绝注入并返回可读诊断。

## 连接和配对

Bridge 生成一次性 pairing JSON，其中包含设备 id、短期 secret、WSS URL 和证书 fingerprint。手机扫描二维码或粘贴 JSON 后，Bridge 只保存 token hash，Android 使用 secure storage 保存 token。

设备可以在本机 admin 页面列出和撤销。admin HTTP 只监听回环地址；公网或 LAN 连接只转发 WSS，并保持证书 fingerprint 不变。

## 数据边界

- UI 状态只展示 Bridge、backend、Frida、WSS 和事件缓存的运行信息。
- 手机 token、Codex credentials、密码和私钥不进入 Desktop renderer。
- 日志只保留版本、设备、backend、thread、turn、request id、错误码和耗时等 metadata。
- Bridge 不提供任意 shell、文件、IPC channel、动态 JavaScript 或通用 tool call。

## 故障处理

先检查 Desktop 版本、Frida helper、证书文件、WSS 可达性和 pairing 是否过期。未知 backend generation、已撤销设备和未注册 capability 应返回错误，不应自动重试副作用请求。
