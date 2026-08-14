# Zoji 基础架构

## 客户端

`SwiftUI View → AppStore → Repository → SwiftData ↔ Private CloudKit`

- SwiftData 是本机权威副本，保证启动、弱网和离线状态可用。
- CloudKit 只使用用户私有数据库，由系统在同一 Apple 账号的设备间同步。
- App 不维护 Zoji 用户账号、Token、自建 API、服务器数据库或对象存储。
- View 不直接操作 `ModelContext`；提醒计算与 `UserNotifications` 调度保持分离。
- 医院地图属于外部查询能力：模拟器使用 MapKit，境内真机优先高德 POI，失败时回退 MapKit。

## 数据策略

- SwiftData/CloudKit：宠物资料、健康记录、提醒规则、头像、病例图片和 PDF。
- 本机：主题、显示偏好、通知权限、缩略图和其他可重建缓存。
- 每条数据使用稳定 UUID；历史 `ownerID`、`revision` 和 `syncState` 字段仅用于兼容旧本地数据库，不再参与服务器协议。
- 删除保留 tombstone 字段，以便 CloudKit 在设备间传播删除结果。
- App 进入前台或用户手动刷新时重新读取 SwiftData，呈现系统已导入的 CloudKit 变更。

## 降级行为

- 未登录 iCloud、iCloud 空间已满或服务暂时不可用时，数据继续保存在本机。
- “我的”页面显示 iCloud 账号状态，不提供自建账号登录或退出入口。
- 当前免费的 Xcode `Personal Team` 不支持 iCloud；Debug 使用本地配置。付费会员激活后再给 Debug 开启 CloudKit entitlement。

## 隐私边界

- 宠物健康数据不进入公共数据库。
- 病历 OCR 优先使用 Apple Vision 在设备端完成。
- 医院搜索只在用户使用该功能时向地图服务发送必要位置范围。
- App 不申请本地网络权限，也不放开任意 HTTP 请求。
