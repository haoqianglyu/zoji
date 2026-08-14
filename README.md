# 爪记 Zoji

爪记是一款面向宠物主人的 iPhone 健康记录与就医辅助 App，采用“本地优先 + 私有 iCloud 同步”架构。

## 当前架构

- `frontend/`：正在使用的 iOS 17+ SwiftUI App，包含宠物档案、健康记录、图片/PDF 附件、提醒和医院地图。
- `docs/`：产品与历史设计资料；当前数据架构以 `docs/architecture.md` 为准。

App 不需要 Zoji 账号、手机号验证码、微信登录、ECS、OSS 或 PostgreSQL。用户操作先保存到本机 SwiftData；具备 CloudKit capability 的构建会由系统同步到用户自己的私有 iCloud 空间。没有登录 iCloud或网络不可用时，App 仍可本地使用。

## 运行 iOS App

1. 用 Xcode 打开 `frontend/Zoji.xcworkspace`。
2. 选择 iPhone 模拟器或已连接的 iPhone。
3. 点击运行（▶）或按 `⌘R`。

当前 Xcode 使用免费的 `Personal Team`，它不支持 iCloud capability，因此 Debug 开发版仅使用本地存储。加入每年 99 美元的 Apple Developer Program 后即可启用并测试 CloudKit。Release 配置已预留 CloudKit container：`iCloud.com.haoqianglyu.zoji.dev`。

## 开发原则

- 数据写入先在本机成功，再由系统自动进行 iCloud 同步。
- 用户私有数据不写入公共 CloudKit 数据库。
- View 不直接访问 SwiftData `ModelContext`，统一通过 Repository/Store。
- 提醒规则同步；通知授权和已调度通知由每台设备本地管理。
- 图片和 PDF 应限制大小并允许压缩，避免过度占用用户 iCloud 空间。
- 疫苗周期仅作为可编辑建议，不能表达成医疗结论。
- 高德 Key 等本机密钥不得提交仓库。
