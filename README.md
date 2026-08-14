# 爪记 Zoji

爪记是一款面向宠物主人的 iPhone 健康管理与就医辅助 App。它可以集中管理宠物档案、体重变化、健康记录、附件和提醒，并帮助用户查找附近的宠物医院。

## 主要功能

- 管理多只宠物的资料、头像、生日、品种、性别和体重
- 记录疫苗、驱虫、用药、就诊及自定义健康事件
- 查看体重趋势和健康时间线
- 创建周期提醒及疫苗、驱虫快捷计划
- 添加图片和 PDF 附件，并在设备端识别病历文字
- 查找、收藏附近的宠物医院
- 按宠物邀请家人共同查看或维护资料
- 支持中英文、主题色、深浅色外观和自定义单位

## 技术与数据

- iOS 17+
- SwiftUI
- SwiftData
- CloudKit 私有数据库
- UserNotifications
- MapKit；中国境内真机可使用高德地图搜索 SDK

数据采用本地优先方式：操作会先保存到设备，启用 iCloud 后由系统同步到用户自己的私有 iCloud 空间。没有网络时仍可使用本地数据。

## 项目结构

- `frontend/`：iOS App、Xcode 工程、资源和测试
- `docs/`：产品与架构文档
- `.github/workflows/ci.yml`：iOS 自动构建检查

## 本地运行

1. 安装 Xcode 和 CocoaPods。
2. 在 `frontend` 目录执行 `pod install`。
3. 用 Xcode 打开 `frontend/Zoji.xcworkspace`。
4. 选择 iPhone 模拟器或已连接的 iPhone，点击运行（▶）。

也可以在命令行验证模拟器构建：

```bash
cd frontend
xcodebuild \
  -workspace Zoji.xcworkspace \
  -scheme Zoji \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 本机配置

如需在中国境内真机使用高德医院搜索，将示例配置复制为本机配置：

```bash
cp frontend/Config/Secrets.xcconfig.example frontend/Config/Secrets.xcconfig
```

然后填写高德 iOS Key：

```xcconfig
AMAP_API_KEY = 你的高德iOSKey
```

`Secrets.xcconfig` 已被 Git 忽略，不会提交到仓库。Key 需绑定 Bundle ID `com.haoqianglyu.zoji`。

## iCloud

CloudKit 同步需要有效的 Apple Developer Program 资格及相应 capability。未配置 CloudKit 的开发构建会继续使用本地 SwiftData。

当前 CloudKit container：`iCloud.com.haoqianglyu.zoji`。
