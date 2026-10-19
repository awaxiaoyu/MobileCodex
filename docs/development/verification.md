# 开发验证

本文记录公开仓库可复现的验证项，不包含本机路径、token、pairing secret、真实聊天内容或内部证据文件。

## Node Bridge

~~~powershell
pnpm typecheck
pnpm test
~~~

测试覆盖 Bridge envelope 校验、设备配对和撤销、WSS 认证、RPC 路由、审批仲裁、请求去重、generation、事件缓存、snapshot、artifact scope 和 NativePipe framing。

## Android

~~~powershell
cd apps/android
flutter pub get
flutter analyze
flutter test
~~~

Flutter 测试使用 mock Bridge，覆盖 widget、配对输入、证书 pin 错误和连接状态。它不等同于实体设备或真实 Desktop 验收。

## 集成 smoke test

以下命令需要兼容版本的 Codex Desktop 和本机 Frida/证书环境：

~~~powershell
pnpm smoke:frida
pnpm smoke:desktop
pnpm smoke:mobile
~~~

集成测试应记录版本、关联 id、计数和错误码，不记录凭据、完整任务文本或本机路径。

## 发布前检查

- Android CI 成功并上传 debug APK；
- README、协议 schema、示例和版本兼容表同步；
- .local/、证书、token、日志、构建目录和本机证据未进入 Git；
- 真实设备上的配对、撤销、重连、锁屏恢复和附件分享已单独验收；
- 未把 fixture、mock 或单机 Desktop 实测描述成普遍兼容。
