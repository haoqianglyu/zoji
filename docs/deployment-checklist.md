# 部署与 Apple 配置清单

## Apple Developer（T03 前完成）

- 确定正式 Bundle Identifier，替换 `com.example.zoji`。
- 为 App ID 开启 Sign in with Apple capability。
- 记录 Team ID、Key ID、Service ID（如 Web 回调需要）和回调地址。
- Apple 私钥只放密钥管理服务，不提交仓库，也不打包进 App。
- 在 App 内实现退出、账号删除和 Apple 凭证撤销后的恢复流程。

## 后端环境

- 为 development、staging、production 分别创建 PostgreSQL、私有 R2 桶和密钥。
- 配置 TLS、短时签名 URL、结构化日志、健康检查和错误监控。
- 在 staging 运行 `prisma migrate deploy` 并演练备份恢复后再迁移生产。
- 日志禁止包含健康记录正文、访问令牌、Apple token 和完整附件 URL。

## 发布前

- iOS Release 与后端 production build 通过。
- 数据库迁移、权限隔离、双设备同步、离线恢复和附件失败重试通过。
- 通知允许/拒绝/后续开启、定位允许/拒绝、无结果和弱网均有可恢复界面。
- App Privacy、权限描述、隐私政策和商店截图与真实功能一致。

