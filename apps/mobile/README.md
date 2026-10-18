# Mobile Codex

Flutter Android/iOS 首版。连接自有 Windows Bridge，在手机继续 Desktop 聊天。

打开 Bridge 生成的 `.local/pairing.json`，在手机“连接电脑”中粘贴。此信息 2 分钟有效、只能使用一次；配对 token 保存到 OS secure storage，应用下次启动会自动恢复并重连，不需要再次配对。TLS 使用电脑证书 SHA-256 pin。公网连接需要 VPN、端口转发或 relay 提供 `wss://.../ws` 可达地址；Bridge 不会把 admin HTTP 暴露到公网。之后打开聊天列表，选择已有聊天或在所选已有项目新建聊天。

已实现文字任务、model/effort、Default/Plan、流式回答、Steer/Interrupt、审批/用户问题、基础 MCP 表单、Diff、附件下载与原生分享、重连与请求结果查询。复杂 MCP schema 和 OAuth 仍提示到电脑处理。

```powershell
../../.local/flutter/bin/flutter.bat pub get
../../.local/flutter/bin/flutter.bat analyze
../../.local/flutter/bin/flutter.bat test
../../.local/flutter/bin/flutter.bat build apk --debug
```

本机 analyze、两项测试和 Android assets bundle 编译通过。debug APK 因 Gradle 下载超时尚未生成；实体手机及 iOS 构建尚未验收。首版没有后台推送、relay、文件树或 Terminal 页面。

GitHub Actions 的 `iOS App` workflow 在 macOS runner 上构建 unsigned IPA 和 Xcode archive。仓库未配置 Apple signing certificate 或 provisioning profile，因此该 IPA 只能用于构建产物验证，不能直接安装到真机。
