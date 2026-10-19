# MobileCodex Android

这是 MobileCodex 的 Flutter Android 客户端。它连接同一局域网或 VPN 中的 Windows Bridge，让用户在手机上继续查看和操作 Codex Desktop 任务。

## 开发环境

- Flutter 3.47.7；
- Dart 3.13.5；
- Android SDK 和 JDK 17；
- 已启动的 Bridge（真实连接测试需要）。

## 本地运行

~~~powershell
flutter pub get
flutter analyze
flutter test
flutter run
~~~

构建 debug APK：

~~~powershell
flutter build apk --debug
~~~

## 连接 Bridge

1. 在电脑上按根目录 README 启动 Bridge。
2. 在 Bridge 设置中生成一次性 pairing JSON 或二维码。
3. 在 Android 应用的“连接电脑”页面粘贴 JSON，或扫描二维码。
4. 配对成功后，从聊天列表选择已有项目和聊天。

pairing secret 只能使用一次并且短期有效。客户端将 token 写入 Android secure storage，并对 Bridge 证书执行 SHA-256 pinning。公网使用前请先配置 VPN 或受控的 WSS 入口；不要暴露 Bridge 的本机 admin HTTP 端口。

## 已实现功能

- 项目与聊天列表、读取、新建和恢复；
- Agent 任务、流式回答、Default/Plan、model/effort；
- Steer、Interrupt、用户问题和支持的审批表单；
- Diff、任务附件的下载和原生分享；
- 断线重连、事件恢复和请求状态查询。

Terminal、通用文件浏览、任意路径读写、Desktop 窗口控制和账号配置不属于手机端接口。需要这些能力时，仍通过聊天请求电脑上的 Agent 执行。

## 测试说明

flutter test 使用本地 mock Bridge 验证 widget、配对和连接错误；它不会连接真实 Desktop。真实设备验收需要单独检查 LAN/VPN、锁屏恢复、证书更新和任务附件分享。
