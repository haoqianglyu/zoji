# AGENTS.md — 爪记 Zoji

给 AI 编码助手（Codex、Claude 等）的项目说明。人类开发者请先看 `README.md` 和 `NEXT_SESSION_HANDOFF.md`。

## 项目概况

- iPhone App，iOS 17+，SwiftUI + SwiftData，本地优先。
- 同步：CloudKit 私有数据库；家庭共享走 CKShare / shared database（Owner / Editor / Viewer）。
- 地图：模拟器和境外用 MapKit；中国境内真机用高德搜索 SDK，失败回退 MapKit。
- 代码在 `frontend/`：`Zoji/App`、`Core`、`DesignSystem`、`Features`；测试在 `frontend/ZojiTests`。
- `backend/`、`infra/` 是历史代码，不要修改或依赖。

## 构建与测试

```bash
cd frontend
pod install
xcodebuild -workspace Zoji.xcworkspace -scheme Zoji \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

提交 PR 前确保测试全部通过；新增逻辑尽量配单元测试。

## 约定

- 用户可见文字一律走 `Localizable.xcstrings`，中英文都要有，不要硬编码。
- 优先使用系统组件（TabView、NavigationSplitView、toolbar 等），不要自己写死布局尺寸。
- 保存操作先写本地、立即更新界面，再异步同步；不要在主线程等网络。
- 提交信息用 Conventional Commits（`feat:` / `fix:` / `chore:` …）。

## 不能做的事

- 不提交高德 Key、证书、描述文件、Apple 账号凭证或任何 secrets。
- 健康资料、图片、PDF 只能存在本机、用户私有 iCloud 或被明确邀请的 CloudKit share，不得发往第三方服务。

## Review guidelines

审查 PR 时重点看：

1. **数据安全**：SwiftData 模型改动是否 CloudKit 兼容（可选属性/默认值、无唯一约束），会不会导致已上线用户的数据迁移失败或丢失。
2. **家庭共享**：Owner / Editor / Viewer 权限是否被正确遵守；Viewer 不能有编辑入口；并发写入是否会产生重复记录。
3. **隐私**：有没有把用户数据、照片、病历发到网络或打印进日志；有没有提交 Key 或凭证。
4. **本地化**：新增文字是否中英文齐全。
5. **主线程**：有没有阻塞主线程的同步 I/O 或网络请求。
6. 纯格式、命名偏好这类问题标为低优先级，不要阻塞合并。
