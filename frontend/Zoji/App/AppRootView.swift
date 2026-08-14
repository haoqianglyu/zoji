import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPrivacyConsent.storageKey) private var hasPrivacyConsent = false
    @State private var shareAcceptance = FamilyShareAcceptanceState.shared
    @State private var shareAcceptanceError: String?

    var body: some View {
        Group {
            if !hasPrivacyConsent {
                PrivacyConsentView {
                    hasPrivacyConsent = true
                }
            } else {
                RootTabView()
                    .task {
                        await reloadDataAndSharedSnapshots()
                        familyStore.startSync()
                    }
                    .transition(.opacity)
            }
        }
        .overlay {
            if shareAcceptance.isLoading {
                FamilyShareLoadingOverlay(title: shareAcceptance.title)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shareAcceptance.isLoading)
        .onChange(of: scenePhase) { _, phase in
            guard hasPrivacyConsent else { return }
            if phase == .active {
                Task {
                    if shareAcceptance.isLoading {
                        await finishAcceptedShareLoading()
                    } else {
                        await reloadDataAndSharedSnapshots()
                        familyStore.retrySync()
                    }
                }
            } else if phase == .background {
                familyStore.startSync()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FamilySharingService.pendingChangesDidUpdateNotification)) { _ in
            familyStore.startSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: FamilySharingService.didAcceptShareNotification)) { notification in
            if let error = notification.userInfo?["error"] as? Error {
                shareAcceptanceError = String(
                    localized: "接受邀请失败：\(error.localizedDescription)",
                    locale: L10n.locale
                )
                shareAcceptance.finish()
            } else {
                Task { await finishAcceptedShareLoading() }
            }
        }
        .alert("家庭共享", isPresented: Binding(
            get: { shareAcceptanceError != nil },
            set: { if !$0 { shareAcceptanceError = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(shareAcceptanceError ?? "请稍后重试。")
        }
        .alert("家庭共享动态", isPresented: Binding(
            get: { familyStore.pendingActivity != nil },
            set: { isPresented in
                if !isPresented {
                    Task { await familyStore.acknowledgeActivities() }
                }
            }
        )) {
            Button("知道了") {
                Task { await familyStore.acknowledgeActivities() }
            }
        } message: {
            Text(familyStore.pendingActivity?.message ?? "家庭共享成员已发生变化。")
        }
    }

    private func finishAcceptedShareLoading() async {
        guard PersistenceController.isCloudKitConfigured else {
            shareAcceptance.finish()
            return
        }

        // CloudKit can briefly report acceptance before the new shared zone is
        // queryable. Keep the progress UI visible and retry that propagation gap.
        for attempt in 0 ..< 8 {
            await reloadDataAndSharedSnapshots()
            if acceptedShareIsVisible {
                shareAcceptance.finish()
                return
            }
            if attempt < 7 {
                try? await Task.sleep(for: .milliseconds(700 + attempt * 180))
            }
        }

        shareAcceptance.finish()
        shareAcceptanceError = L10n.string("邀请已接受，但共享宠物资料暂时还没有同步完成。请稍后下拉刷新家庭共享。")
    }

    private var acceptedShareIsVisible: Bool {
        guard let zoneName = shareAcceptance.targetZoneName else {
            return !familyStore.sharedPets.isEmpty
        }
        return familyStore.sharedPets.contains { pet in
            pet.location.zoneName == zoneName && (
                shareAcceptance.targetZoneOwnerName == nil ||
                    pet.location.zoneOwnerName == shareAcceptance.targetZoneOwnerName
            )
        }
    }

    private func reloadDataAndSharedSnapshots() async {
        await appStore.reloadPersistedAndFamilyData(using: familyStore)
    }
}

private struct FamilyShareLoadingOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentSoft)
                        .frame(width: 66, height: 66)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                Text(L10n.dynamic(title))
                    .font(.headline)

                Text("正在安全读取宠物资料、健康记录和提醒…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ProgressView()
                    .tint(AppTheme.accent)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 310)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，请稍候")
    }
}

enum AppPrivacyConsent {
    static let storageKey = "zoji.privacy-consent.v1"

    static var isGranted: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}

private struct PrivacyConsentView: View {
    let onAgree: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.accentSoft, AppTheme.background],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text("欢迎使用爪记")
                            .font(.largeTitle.bold())
                        Text("请先阅读并同意隐私说明")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        consentRow(
                            icon: "lock.shield.fill",
                            title: "数据用于提供服务",
                            detail: "宠物资料和健康记录会先保存在本机；开启 iCloud 后，可通过你的私有 iCloud 空间在 Apple 设备间同步。"
                        )
                        consentRow(
                            icon: "location.fill",
                            title: "附近宠物医院",
                            detail: "医院功能会在你允许定位后，将附近区域位置用于搜索医院。境内 POI 由北京高德图强科技有限公司的高德地图搜索 SDK 提供。"
                        )
                    }
                    .padding(20)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Link(
                        "查看高德地图开放平台隐私权政策",
                        destination: URL(string: "https://lbs.amap.com/pages/privacy/")!
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)

                    Text("点击“同意并继续”，表示你已了解上述信息，并同意爪记在提供相应功能时按说明处理必要信息。正式发布前还会补充完整的《用户协议》和《隐私政策》页面。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onAgree) {
                        Text("同意并继续")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 54)
                .padding(.bottom, 36)
            }
        }
    }

    private func consentRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.dynamic(title))
                    .font(.headline)
                Text(L10n.dynamic(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    AppRootView()
        .environment(AppStore.preview)
        .environment(FamilySharingStore())
}
