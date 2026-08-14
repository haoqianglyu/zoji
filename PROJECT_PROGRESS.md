# 爪记 Zoji 项目进度

> 最后更新：2026-08-13  
> 当前阶段：本地优先版本功能完善，家庭 CloudKit 共同编辑已实现，等待双真机在线验收。

## 当前状态

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| App 基础 | ✅ | SwiftUI、四 Tab、主题、Logo、隐私同意页 |
| 宠物档案 | ✅ | CRUD、多宠、品种、头像、生日、性别、体重 |
| 健康记录 | ✅ | CRUD、七种类型、详情、费用、机构、时间线 |
| 病例附件 | ✅ | 最多 9 个图片/PDF、3×3 网格、放大/PDF 预览、图片自动压缩、单文件与总容量保护 |
| 病例识别 | ✅ | 与普通附件分区，使用 Apple Vision 本机 OCR |
| 健康提醒 | ✅ | 自定义天数、周期、提前通知、完成顺延、防重复 |
| 护理计划 | ✅ | 猫狗疫苗和驱虫模板，可逐项选择 |
| 医院 | ✅ v1 | 真机高德、模拟器 MapKit、列表/地图、拨号、导航、收藏 |
| 本地数据 | ✅ | SwiftData Repository，本地离线可用 |
| 手动备份 | ✅ | 完整 JSON 导出、关系/大小校验、合并恢复，包含附件 |
| 同账号换机同步 | ✅ | iPhone → 同 iCloud 模拟器已同步宠物、头像、健康记录、提醒，以及 4 张图片和 1 个 PDF |
| 家庭共享 | 🟡 功能实现完成 | 按宠物 CKShare、可更改/仅查看、首页/记录页入口、共同编辑、防重复完成及本地优先待同步队列已完成；待双账号真机验收 |
| 发布加固 | ⬜ | 导出、隐私政策、无障碍、附件限制、TestFlight 回归 |

## 当前数据架构

`SwiftUI → AppStore → Repository → SwiftData ↔ Private CloudKit`

- 写入先在本机完成，断网仍能使用。
- 付费 Team 构建可使用用户自己的私有 iCloud 在同一 Apple 账号设备间同步。
- 提醒规则可以同步；系统通知由每台设备分别安排。
- 家庭多人协作使用 CloudKit shared database；宠物、健康记录、附件和提醒分记录保存，拥有者本机保留 SwiftData 镜像。
- 普通编辑先写本地并立即返回，随后由持久化队列上传共享 CloudKit；断网或退出 App 后，待同步任务会在下次启动/回到前台时继续。
- “完成提醒”、接受邀请、退出共享等需要服务器裁决的操作仍等待 CloudKit 确认，避免多人重复完成或共享状态误判。
- App 不需要 Zoji 账号、手机号验证码、自建 API、ECS、OSS 或 PostgreSQL。

## 账号与发布

- Debug 和 Release 均已选择用户自己的付费 Apple Developer Team。
- 正式 Bundle ID 为 `com.haoqianglyu.zoji`，CloudKit container 为 `iCloud.com.haoqianglyu.zoji`。
- App Store 开发者名称、协议、税务、收款、CloudKit 数据和应用控制权均属于用户自己的账号。

## 最近验证

- Debug 通用 iOS Simulator 构建成功。
- iPhone 17 Pro 模拟器测试成功。
- 19 项单元测试全部通过，无失败；已覆盖提醒规则、主题、备份、家庭共享载荷、附件压缩与容量边界、SwiftData 持久化，以及待同步队列持久化、共享缓存和撤销共享清理。
- Debug 与 Release 真机构建成功；Xcode 已生成包含 iCloud、CloudKit、推送和后台远程通知权限的正式描述文件。
- 正式签名构建已安装并成功启动于 `gigigi` iPhone。
- `gigigi` 已确认“本机 + 私有 iCloud / iCloud 已开启”，高德 Key 也已改绑正式 Bundle ID。
- 同一 iCloud 账号的 iPhone 17 Pro 模拟器已自动拉取“布布”、2 条健康记录、2 条提醒和宠物头像，基础 CloudKit 跨设备同步验证通过。
- 同一模拟器已继续拉取真机上传的 4 张图片和 1 个 PDF，CloudKit 大附件同步验证通过。
- 病例图片最长边自动压到 2048 像素并以约 2.5 MB 为优先目标；单 PDF 限 25 MB，单条记录附件总计限 75 MB。
- 朋友发布交接清单已转为历史文档，后续不再需要朋友签名或发布。
- 家庭共享已从只读快照升级为分记录的 CloudKit 共同编辑：邀请时可选“可更改/仅查看”，共享宠物出现在首页和记录页，附件仍支持 3×3 与滑动预览。
- 同一提醒的完成操作采用 CloudKit `ifServerRecordUnchanged` 原子校验，其他成员重复点击不会新增第二条记录。
- 宠物资料、健康记录、附件和提醒编辑已改为本地即时保存；共享云端同步状态可见，失败可重试，重新进入 App 会自动续传。
- 2026-08-13 使用完整 workspace 构建成功，19 项测试全部通过。

## 下一步

1. 两台不同 Apple 账号的 iPhone 联网后安装最新构建。
2. 验收按宠物邀请、可更改权限、双向编辑、附件和撤销共享。
3. 验收家庭共享和隐私页面。
4. 补齐隐私政策、无障碍和小屏适配。
5. TestFlight 双设备回归。

完整顺序见 [ROADMAP.md](ROADMAP.md)，开发接力信息见 [NEXT_SESSION_HANDOFF.md](NEXT_SESSION_HANDOFF.md)。
