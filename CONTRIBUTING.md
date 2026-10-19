# Contributing

感谢你对 MobileCodex 的兴趣。

## 开始之前

请先阅读 README 了解 Bridge 的网络边界、支持的 Desktop 版本和手机端不提供的能力。提交前不要把 pairing JSON、TLS key、token、真实聊天内容、工作区路径或本地证据文件加入 Git。

## 本地检查

在仓库根目录运行：

~~~powershell
pnpm install --frozen-lockfile
pnpm typecheck
pnpm test
~~~

修改 Android 代码时，再运行：

~~~powershell
cd apps/android
flutter pub get
flutter analyze
flutter test
~~~

## 提交规范

- 保持改动聚焦；Bridge 协议变化同步更新 schema 和文档。
- 新增手机能力时说明 capability、权限边界、断线恢复和测试方法。
- 不要通过手机 API 暴露任意 shell、文件系统或原始私有 IPC。
- 不提交 build 输出、.local 数据、证书、token 或机器特有路径。
- Pull request 描述应说明行为变化和验证结果。
