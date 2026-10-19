# Security Policy

## 报告安全问题

请不要在公开 issue 中发布 pairing secret、TLS private key、token、真实任务内容或可复现的远程利用细节。请通过 GitHub Security Advisories 或项目维护者配置的私密渠道报告，并附上：

- 受影响的 commit、版本和运行环境；
- 复现步骤和最小化日志；
- 影响范围、是否需要已配对设备和建议修复方向。

## 安全边界

MobileCodex 面向已经配对的个人设备。Bridge 默认使用证书 pinning、短期一次性 pairing 和设备撤销；这不替代防火墙、VPN、操作系统更新或正确的网络隔离。不要把 admin HTTP 端口暴露到公网。
