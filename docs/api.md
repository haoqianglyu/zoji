# `/v1` API 清单

| 模块 | 路由 | 状态 |
| --- | --- | --- |
| Health | `GET /v1/health` | 已实现 |
| Auth | `POST /v1/auth/apple` | T03 占位 |
| Auth | `POST /v1/auth/wechat` | T03 待建立 |
| Auth | `POST /v1/auth/phone/send-code`、`POST /v1/auth/phone/verify-code` | 防刷与验证框架已实现，待接阿里云 |
| Auth | `POST /v1/auth/refresh` | 已实现 |
| Auth | `POST /v1/auth/logout` | 已实现 |
| Users | `GET /v1/users/me`、`DELETE /v1/users/me` | T03 占位 |
| Pets | `GET/POST /v1/pets`、`PATCH/DELETE /v1/pets/:petID` | T05 占位 |
| Records | `GET/POST /v1/records`、`PATCH/DELETE /v1/records/:recordID` | T05 占位 |
| Reminders | `GET/POST /v1/reminders`、`POST /v1/reminders/:id/complete` | T05 占位 |
| Attachments | `POST /v1/attachments/upload-url`、`POST /v1/attachments/:id/download-url` | T08 占位 |
| Hospitals | `POST /v1/hospitals/resolve`、收藏相关端点 | T09 占位 |
| Sync | `POST /v1/sync/push`、`GET /v1/sync/pull?cursor=` | T06 占位 |

## T03 登录契约

三种登录成功后统一返回：

```json
{
  "user": {
    "id": "uuid",
    "displayName": "团子的家长",
    "linkedProviders": ["apple", "phone"]
  },
  "session": {
    "accessToken": "short-lived-token",
    "accessTokenExpiresInSeconds": 900,
    "refreshToken": "rotating-refresh-token",
    "refreshTokenExpiresInSeconds": 2592000
  },
  "isNewUser": false
}
```

手机号采用两步挑战：

1. `POST /v1/auth/phone/send-code` 提交 E.164 手机号，返回 `challengeID`、验证码有效秒数和重发等待秒数。
2. `POST /v1/auth/phone/verify-code` 只提交 `challengeID + code`，由服务端读取挑战中绑定的手机号。

发送验证码时 iOS 应附加本次安装随机生成的 `x-device-id` 请求头。它只作为补充频率限制信号，服务端不会把它当作可信身份。

当前防刷默认值：同一手机号 60 秒内不可重发、每小时最多 5 次；同一 IP 每小时最多 20 次；同一设备标识每小时最多 10 次。验证码 5 分钟过期，最多尝试 5 次。所有数值都可通过后端环境变量调整。

开发环境固定使用 `SMS_DEVELOPMENT_CODE=123456`，但接口响应和服务端日志都不会返回验证码；生产环境会强制禁用开发短信模式，阿里云未配置时返回 `auth_provider_unavailable`。

### 会话行为

- access token 为 HS256 JWT，默认有效期 15 分钟，包含用户 ID、session ID 和唯一 token ID。
- refresh token 为 256-bit 随机不透明字符串，默认有效期 30 天；数据库只保存带服务端密钥的 HMAC-SHA256 摘要。
- 每次调用 `POST /v1/auth/refresh` 都会原子撤销旧 session 并签发一套新 token；同一个 refresh token 不能重复使用。
- `POST /v1/auth/logout` 撤销对应 session，多次调用保持幂等。
- Apple、微信和手机号登录端点暂时返回 `501 auth_not_implemented`，待身份提供商服务接入后调用同一会话签发层。

三种身份提供商完成凭证校验后，只把规范化的 `provider + providerSubject` 交给统一身份服务。该服务会更新已有身份的最后登录时间，或原子创建 `User + AuthIdentity`，再调用统一会话层签发 token。并发首次登录由数据库唯一约束收敛到同一个用户，不会生成重复身份。

稳定认证错误码：

| 错误码 | 含义 |
| --- | --- |
| `auth_not_implemented` | 接口契约已存在，真实提供商尚未接入 |
| `auth_invalid_credential` | Apple/微信登录凭证无效 |
| `auth_code_invalid` | 短信验证码错误 |
| `auth_code_expired` | 短信验证码已过期 |
| `auth_rate_limited` | 请求过于频繁 |
| `auth_provider_unavailable` | 第三方认证服务暂时不可用 |
| `auth_identity_conflict` | 身份已经绑定到其他 Zoji 用户 |
| `auth_session_expired` | refresh session 已过期 |
| `auth_session_revoked` | refresh session 已撤销 |

统一错误格式：

```json
{
  "error": {
    "code": "BadRequestException",
    "message": "输入无效",
    "requestId": null
  }
}
```

OpenAPI 页面默认位于 `/docs`。后续客户端模型生成以 OpenAPI 为共同契约，不手工维护两套字段名。
