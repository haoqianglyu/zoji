# 爪记 Zoji 下一阶段开发交接

> 更新时间：2026-08-13  
> 当前架构：SwiftUI + SwiftData，本地优先；付费 Team 构建使用私有 CloudKit。

## 当前可用功能

- 宠物档案、健康记录、图片/PDF 附件、本机 OCR、提醒和医院地图均已形成可操作闭环。
- Debug 和 Release 均使用用户自己的付费 Team。
- 正式 Bundle ID 已确定为 `com.haoqianglyu.zoji`，CloudKit container 为 `iCloud.com.haoqianglyu.zoji`。
- Xcode 已为正式 App ID 生成包含 CloudKit/推送权限的真机描述文件；Debug、Release 真机构建均成功。
- Debug 正式签名构建已安装并启动于 `gigigi` iPhone，下一步在 App 内确认 iCloud 状态并做双设备数据同步测试。
- `gigigi` 已确认私有 iCloud 状态为“已开启”；高德 Key 已绑定正式 Bundle ID。
- iPhone → 同 iCloud 模拟器同步已验证：宠物、头像、健康记录和提醒均成功落地；下一步验证图片/PDF 病例附件。
- 模拟器使用 MapKit 医院查询；境内真机可使用高德 SDK，失败会回退 MapKit。
- “我的”页面提供同步状态、家庭共享说明、主题、系统权限入口和数据隐私说明。
- 家庭共享已使用 CKShare/shared database 实现：宠物根记录、健康记录、附件和提醒分别保存；旧只读快照可兼容迁移。
- 共享宠物已进入首页和健康记录页；Editor 可编辑资料、记录、附件和提醒，Viewer 只读。
- 多人完成同一提醒时使用 CKRecord change tag 原子写入，避免重复健康记录。
- 共享编辑已改为本地优先：普通资料/记录/附件/提醒先保存并立即更新界面，持久化队列异步上传；失败后在前台自动重试，也可在“我的”中手动重试。

## 最近完成

- 移除 iOS App 对短信登录、自建 API 和服务器同步的依赖。
- SwiftData 模型调整为 CloudKit 兼容形式，头像和附件使用外部存储。
- 增加家庭共享产品入口，明确共享范围和拥有者/可编辑/仅查看权限。
- 免费开发版不会展示无效邀请按钮；CloudKit 邀请需付费 Team 下真机联调。
- 已加入完整备份导出和合并恢复，包含宠物、记录、提醒、图片和 PDF。
- Debug 模拟器构建成功，11 项单元测试全部通过；其中新增了宠物、健康记录、附件和提醒的 SwiftData 持久化测试。
- 用户已开通自己的付费 Apple Developer 账号，不再需要朋友签名、联调或发布。

## 紧接着做

1. 连接 `gigigi` 和“幸運的小沈”，安装最新正式签名 Debug 构建。
2. `gigigi` 从“我的 → 家庭共享”邀请另一账号，权限选择“可更改”。
3. 在另一台手机接受后，分别新增一条带图片/PDF 的记录和完成一次提醒，再回到拥有者手机刷新核对。
4. 测试一次断网编辑：保存后应立即返回；恢复网络并重新进入 App 后，另一台手机应收到改动。
5. 在 Apple 系统共享管理面板切为“仅查看”并撤销，核对编辑入口、访问权限和旧待同步任务是否被清理。
6. 继续隐私政策、无障碍、小屏和 TestFlight 回归。

## 验证命令

```bash
cd /Users/haoqianglyu/zoji/frontend
xcodebuild -workspace Zoji.xcworkspace -scheme Zoji \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 重要边界

- 不提交高德 Key、证书、配置文件或朋友的 Apple 账号凭证。
- 不共享 Apple ID 密码和双重认证验证码。
- 图片/PDF 和健康资料只能进入本机、用户私有 iCloud 或被明确邀请的 CloudKit share。
- 旧 `backend/` 和 `infra/` 是历史代码，不是运行或发布依赖。
