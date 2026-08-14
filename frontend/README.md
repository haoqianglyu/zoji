# Zoji iOS

`Zoji.xcworkspace` 是 iOS 17+ SwiftUI 工作区。接入 CocoaPods 后始终打开 workspace，不要单独打开 `Zoji.xcodeproj`。

Zoji 采用本地优先架构：宠物档案、健康记录、附件和提醒先写入 SwiftData；启用 CloudKit 的正式构建会自动同步到用户的私有 iCloud 数据库。

目录职责：

- `App/`：App 入口、全局 Store 和底部导航。
- `Core/Domain/`：不依赖 UI 的领域模型与提醒日期纯函数。
- `Core/Persistence/`：CloudKit 兼容的 SwiftData 模型和容器。
- `Core/Repositories/`：View 与本地持久化之间的边界。
- `DesignSystem/`：颜色、卡片和共享组件。
- `Features/`：首页、记录、医院、我的和宠物资料。
- `ZojiTests/`：提醒日期等确定性单元测试。

Debug 和 Release 均使用正式 Bundle ID `com.haoqianglyu.zoji`，并已配置 `ICLOUD_SYNC_ENABLED`、`Zoji/Zoji.entitlements`、CloudKit 和远程通知后台模式。数据始终先写入本地 SwiftData，再同步到用户的私有 iCloud 数据库。

医院页面使用 MapKit；中国境内医院 POI 在真机优先使用高德无 IDFA 搜索 SDK，失败或境外区域自动回退到 MapKit。模拟器只使用 MapKit，以兼容 Apple 芯片。高德 Key 只写入已被 `.gitignore` 排除的 `Config/Secrets.xcconfig`：

```xcconfig
AMAP_API_KEY = 你的高德iOSKey
```

Key 需绑定正式 Bundle ID `com.haoqianglyu.zoji`。依赖变更后，在 `frontend` 目录执行 CocoaPods，再打开 `Zoji.xcworkspace`：

```bash
/usr/bin/ruby -rlogger ~/.gem/ruby/2.6.0/bin/pod install
```

不要在 View 中直接操作 `ModelContext`。图片和 PDF 使用 SwiftData external storage，由 CloudKit 随私有数据库同步；本地通知继续由每台设备分别安排。
