# 发布与 Apple 配置清单

## Apple Developer

- App ID 使用 `com.haoqianglyu.zoji`，启用 iCloud/CloudKit 和 Push Notifications。
- iCloud container 使用 `iCloud.com.haoqianglyu.zoji`，确认开发与发布描述文件都包含该容器。
- 高德 iOS Key 只写入未提交的 `frontend/Config/Secrets.xcconfig`，并确认 Key 的 Bundle ID 限制与正式 App 一致。
- Archive 前确认版本号与 build number 已递增，发布签名中的 `aps-environment` 为 production。

## CloudKit

- 在两台真机上初始化并核对 Development schema，包括 SwiftData 自动生成的类型和 `ZojiFamily*` 家庭共享类型。
- 在 CloudKit Console 将完整 schema 部署到 Production；部署前确认没有误命名的 record type 或 field，因为生产字段不能删除或改名。
- 使用两个不同 Apple ID 验证 Owner、Editor、Viewer、停止共享、成员退出、离线修改恢复和附件同步。
- 验证拥有者删除宠物后，家人端不再保留共享僵尸数据。

## 隐私与合规

- 每次 `pod install` 后确认高德 Foundation No-IDFA 与 Search framework 内都有 `PrivacyInfo.xcprivacy`。
- Archive 后生成 Privacy Report，确认包含 App 与高德 SDK 的 required-reason API 声明。
- App Store Connect 的 App Privacy 至少与当前清单一致：精确位置用于 App 功能；不与身份关联的用户标识和产品交互用于高德服务分析；不用于跟踪。
- App 内高德授权、隐私政策、App Store Privacy 与高德官方隐私清单保持一致。
- 将本仓库 `docs/` 中的法律文案同步到 `haoqianglyu/haoqianglyu.github.io` 的 `/zoji/` 目录，并确认以下页面无需登录即可访问：
  - `https://haoqianglyu.github.io/zoji/privacy-policy.html`
  - `https://haoqianglyu.github.io/zoji/terms-of-use.html`
- 用无痕浏览器和 `curl -I` 验证以上 URL 返回 `200`，TLS 有效且没有重定向循环。

## 真机回归

- 中文和英文各走一遍冷启动、首次隐私同意、归档、纪念、恢复、记录生活、健康记录和提醒完成流程。
- 通知分别验证允许、拒绝、从设置重新开启、逾期再次提醒，以及点按通知进入对应提醒。
- 医院页验证定位允许/拒绝、Apple 地图、高德同意/拒绝、空结果、弱网、拨号和收藏同步。
- 使用辅助功能大字号验证首页宠物卡、宠物切换器、记录列表和确认弹窗没有截断或重叠。
- 确认日志没有生活或健康记录正文、访问令牌、高德 Key 或附件内容。

## TestFlight 与商店资料

- Release 构建、完整单元测试和 Archive validation 全部通过后再上传 TestFlight。
- 支持邮箱使用 `zoji.app.support@gmail.com`，并验证能正常收发。
- Support URL、Privacy Policy URL、版本说明、商店截图和功能描述与当前版本一致。
- TestFlight 至少完成一次全新安装和一次覆盖升级；覆盖升级要保留本地数据、iCloud 数据、家庭共享和通知状态。
