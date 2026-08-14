# Zoji 登录与账户方案

> 状态：身份/会话底层、手机号后端、iOS API 客户端与 Keychain 已完成  
> 登录方式：Apple、微信、手机号验证码

## 设计目标

- 一个 Zoji 用户可以绑定多种登录方式。
- 同一个人使用 Apple、微信或手机号登录时，可以进入同一个 Zoji 账户。
- App 不保存 Apple、微信或阿里云的密钥。
- 第三方 token 和短信验证码只提交给后端验证。
- access token 短期有效；refresh token 轮换、哈希保存并支持撤销。
- 注册过账户的用户可以在 App 内发起账号删除。

## 数据结构调整

数据库已经从只支持 `User.appleSubject` 调整为：

```text
User
  id
  displayName
  phone（可选、加密或最小化保存）
  status

AuthIdentity
  id
  userID
  provider：apple / wechat / phone
  providerSubject：Apple sub、微信 unionid/openid 或标准化手机号标识
  createdAt
```

`provider + providerSubject` 必须唯一。账户绑定属于高风险操作，需要用户先完成已有方式的重新验证，不能仅凭客户端传入的 userID 合并。

## API 规划

| 路由 | 作用 |
| --- | --- |
| `POST /v1/auth/apple` | 验证 Apple identity token，创建或恢复 Zoji 会话 |
| `POST /v1/auth/wechat` | 服务端使用临时 code 完成微信 OAuth 验证 |
| `POST /v1/auth/phone/send-code` | 发送短信验证码并执行频率限制、防刷和风控 |
| `POST /v1/auth/phone/verify-code` | 验证手机号和验证码，创建或恢复会话 |
| `POST /v1/auth/refresh` | 轮换 refresh token |
| `POST /v1/auth/logout` | 撤销当前会话 |
| `POST /v1/auth/link/*` | 已登录用户绑定另一种登录方式 |
| `DELETE /v1/users/me` | 账号删除流程 |

## 三种登录的准备条件

### Apple 登录

现在可以开发登录界面、客户端适配层和服务端 token 校验。正式联调前需要：

- Account Holder 确定正式 Bundle Identifier。
- Account Holder 为正式 App ID 开启 Sign in with Apple。
- Account Holder 创建 Sign in with Apple Key，并把 Team ID、Key ID 和私钥安全配置到后端。
- 私钥不得发送到聊天、写进 Xcode 工程或提交仓库。

### 微信登录

现在可以预留客户端适配层和服务端接口。正式联调前需要：

- 注册并认证微信开放平台开发者账号。
- 创建“移动应用”并通过审核。
- 获得 AppID 和 AppSecret。
- 配置 iOS Bundle Identifier、Universal Link 和微信 OpenSDK。
- AppSecret 只能保存在后端。

建议等正式 Bundle Identifier、App 图标、隐私政策 URL 和基础产品页面确定后再提交微信移动应用审核。

### 手机号验证码

现在可以开发验证码页面、倒计时、接口契约和后端防刷框架。正式发送短信前需要：

- 注册并实名认证阿里云账号。
- 开通阿里云“短信认证服务”或传统“短信服务”。
- 创建仅允许短信相关操作的最小权限凭证。
- 后端配置 AccessKey；iOS 客户端绝不能直接持有 AccessKey。
- 开启号码、IP、设备、时间窗口的频率限制以及发送量预警。

个人开发阶段优先考虑阿里云“短信认证服务”，其官方方案可以使用平台提供的签名和模板；如果以后需要“爪记”自定义短信签名，再根据当时的主体资质申请传统短信签名和模板。

## 实现顺序

1. [x] 重构数据库：`User + AuthIdentity + Session`。
2. [x] 定义三种登录 API、错误码和会话响应格式。
3. [x] 实现短期 access token、refresh token 哈希保存、原子轮换、重放拒绝和退出撤销。
4. [x] 实现统一身份服务，通过 `AuthIdentity` 查找或创建 Zoji 用户，并处理并发首次登录。
5. [x] 创建 iOS 登录页和 `AuthStore`，使用本地开发适配器建立状态流转。
6. [x] 实现手机号验证码服务端接口、挑战存储和防刷框架。
7. [x] 建立 iOS `APIAuthClient`、Keychain 会话保存、启动刷新和退出撤销。
8. [ ] 接入阿里云真实短信发送。
9. [ ] 实现 Apple identity token 服务端校验，等待 Account Holder 配置正式 App ID 联调。
10. [ ] 实现微信 OAuth code 服务端交换，等待微信开放平台审核后联调。
11. [ ] 实现登录方式绑定与账号删除。

### iOS 本地登录骨架

- `AppRootView` 根据 `AuthStore` 自动切换登录界面和四 Tab 主界面。
- `AuthStore` 覆盖未登录、认证中、已登录和退出中状态，并集中处理错误提示。
- Debug 构建使用本地适配器：Apple、微信可直接进入体验账户；手机号验证码固定为 `123456`。
- Release 构建不包含可成功登录的本地后门，真实服务未接入时只返回“尚未配置”。
- “我的”页面展示当前登录方式并提供退出入口。
- Zoji session 和稳定安装 ID 已使用 Keychain 保存，不使用 `UserDefaults` 保存 token。

### iOS API 与会话恢复

- Debug 手机号流程调用 `http://localhost:3000/v1`，Apple 与微信仍使用本地模拟适配器。
- 登录成功后 access/refresh token 及过期时间写入 Keychain；安装 ID 也存入 Keychain，用于补充防刷。
- App 启动时使用已保存的 refresh token 调用 `/auth/refresh` 并立即轮换；refresh 过期或无效时清除本机会话。
- 退出登录会调用 `/auth/logout`，即使网络失败也优先删除本机凭证，避免设备继续保持登录。
- Debug 单独允许本地 HTTP；Release 的 Info.plist 不包含任意 HTTP 放行，也不启用模拟登录。
- 真机连接 Mac 上的后端时，`localhost` 需要改成 Mac 的局域网 IP；正式环境必须使用 HTTPS API 域名。

### 阿里云开通时点

现在已经到达可以开通阿里云的节点：本地 API 链路完成后，下一步就是替换开发短信网关。个人开发阶段优先选择阿里云“号码认证服务”中的“短信认证服务”，不选择需要企业资质、自定义签名和模板的传统短信服务。

准备内容：完成实名认证的阿里云账号、可支付余额、一个用于测试的手机号，以及后续创建的最小权限 AccessKey。AccessKey Secret 只能配置在 Zoji 后端，不能写入 Xcode、提交仓库或发送到聊天中。

### 手机号验证码后端框架

- 挑战表不保存手机号或验证码明文：手机号使用 AES-256-GCM 临时加密，检索与频率限制使用带服务端密钥的 HMAC。
- 验证码摘要绑定 challenge ID，比较时使用恒定时间算法；错误验证码只增加尝试次数，不泄露正确性细节。
- 正确验证码通过原子更新抢占 challenge，同一验证码并发提交时只有一个请求能签发会话。
- 默认 5 分钟过期、最多尝试 5 次，并限制手机号、请求 IP 和客户端安装标识的小时发送量。
- 开发模式固定码不会出现在 API 响应或日志中，生产环境禁止启用开发短信网关。
- 反向代理部署时必须正确配置可信代理，否则 `request.ip` 只能看到代理服务器地址。
- 过期 challenge 的定期清理任务会在部署加固阶段加入；当前记录保留用于防刷时间窗口。

## 安全要求

- 验证码只保存不可逆摘要，并设置短有效期和最大尝试次数。
- 不记录验证码、Apple identity token、微信 access token、AppSecret、refresh token 或阿里云 AccessKey。
- 登录接口必须限制手机号、IP、设备和时间窗口请求频率。
- 微信 AppSecret、Apple 私钥和阿里云 AccessKey 只存在于服务端密钥管理系统。
- 客户端 Keychain 只保存 Zoji 的会话凭证，不保存第三方长期密钥。

## 已完成的会话策略

- access token 默认 15 分钟有效，签名密钥、签发方和受众全部从后端环境变量读取。
- refresh token 默认 30 天有效，客户端只收到一次明文，后端只保存 HMAC-SHA256 摘要。
- refresh 采用一次性轮换：事务内撤销旧 session 后创建新 session，并记录 `replacedByID`。
- 并发或重复提交旧 refresh token 时，只有第一次轮换成功，后续请求返回 `auth_session_revoked`。
- logout 接口幂等，已退出或不存在的 token 不泄露会话是否存在。

## 已完成的统一身份策略

- Apple、微信和手机号适配器必须先在服务端验证第三方凭证，统一身份服务不接收未经验证的客户端身份 ID。
- 已存在的 `provider + providerSubject` 会恢复原 Zoji 用户，并更新 `lastUsedAt`。
- 新身份会通过 Prisma 嵌套写入原子创建 `User + AuthIdentity`，不会留下只有用户、没有身份的半成品数据。
- 两个相同身份并发首次登录时，数据库唯一约束只允许一个请求创建账户，另一个请求复用获胜账户。
- Apple 和微信的 subject 区分大小写，不做擅自改写；手机号由短信适配器先规范化为 E.164。
- 不同登录方式不能靠姓名、手机号猜测或客户端 userID 自动合并。用户需要先登录已有账户，再重新验证另一种方式完成显式绑定。
