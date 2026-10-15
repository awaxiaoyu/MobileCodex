# Mobile Codex

Flutter Android/iOS 首版。连接自有 Windows Bridge，在手机继续 Desktop 聊天。

打开 Bridge 生成的 `.local/pairing.json`，在手机“连接电脑”中粘贴。此信息 2 分钟有效、只能使用一次；配对 token 保存到 OS secure storage，TLS 使用电脑证书 SHA-256 pin。之后打开聊天列表，选择已有聊天或在所选已有项目新建聊天。

已实现文字任务、model/effort、Default/Plan、流式回答、Steer/Interrupt、审批/用户问题、基础 MCP 表单、Diff、附件下载与原生分享、重连与请求结果查询。复杂 MCP schema 和 OAuth 仍提示到电脑处理。

```powershell
../../.local/flutter/bin/flutter.bat pub get
../../.local/flutter/bin/flutter.bat analyze
../../.local/flutter/bin/flutter.bat test
../../.local/flutter/bin/flutter.bat build apk --debug
```

本机 analyze、两项测试和 Android assets bundle 编译通过。debug APK 因 Gradle 下载超时尚未生成；实体手机及 iOS 构建尚未验收。首版没有后台推送、relay、文件树或 Terminal 页面。
