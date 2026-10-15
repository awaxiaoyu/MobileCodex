# 后续验收

持续 Frida shared adapter、Desktop live turn 控制、Plan/用户问题、配对/WSS/撤销及 Flutter 第一版已实现，详情见 [验证记录](p0-verification.md)。

1. 解决 Gradle distribution 从 GitHub 下载超时，生成 debug APK，并在实体 Android 上配对。iOS 转 macOS/Xcode 构建。
2. 真实 command/file/permissions/MCP form 各一个请求，检查电脑和手机同时回复时仅提交一次。
3. 实体手机断线/重连、缓存缺失、Bridge/backend 重启、未知 mutation 查询；审批已在电脑解决时手机及时移除。
4. 一个真实任务的 Diff 和结果附件：手机预览/分享、跨任务拒绝、已删除产物诊断。
5. LAN/VPN 防火墙与睡眠/锁屏状态；需通知时再加入 push/relay，当前版本只提供前台连接。
6. 按使用场景推进聊天管理与 Automation/Heartbeat，不扩展已裁掉的 Terminal、通用 fs、Git/Worktree 或 Desktop 布局。

Frida adapter 私有运行时锁在 compatibility.json。独立 DLL/installer 是后续打包方案；没有将 PoC 或 Python helper 宣称为 DLL。
