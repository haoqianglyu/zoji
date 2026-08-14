import SwiftUI

struct AppRootView: View {
    @Environment(\.appColorTheme) private var theme
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
    @Environment(\.appColorTheme) private var theme
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(theme.accentSoft)
                        .frame(width: 66, height: 66)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }

                Text(L10n.dynamic(title))
                    .font(.headline)

                Text("正在安全读取宠物资料、健康记录和提醒…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ProgressView()
                    .tint(theme.accent)
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
    static let storageKey = "zoji.privacy-consent.v2"

    static var isGranted: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}

enum AMapPrivacyConsent {
    enum Status: Int {
        case undetermined = 0
        case agreed = 1
        case declined = 2
    }

    static let storageKey = "zoji.amap-privacy-consent.v1"

    static var status: Status {
        Status(rawValue: UserDefaults.standard.integer(forKey: storageKey)) ?? .undetermined
    }

    static var isGranted: Bool { status == .agreed }
}

enum LegalDocument: String, Identifiable {
    case privacyPolicy
    case termsOfUse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: LegalCopy.text("隐私政策", "Privacy Policy")
        case .termsOfUse: LegalCopy.text("用户协议", "Terms of Use")
        }
    }
}

enum LegalCopy {
    static func text(_ chinese: String, _ english: String) -> String {
        L10n.usesEnglish ? english : chinese
    }
}

private struct PrivacyConsentView: View {
    @Environment(\.appColorTheme) private var theme
    @State private var legalDocument: LegalDocument?
    let onAgree: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.accentSoft, theme.background],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(theme.accent)
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
                            detail: LegalCopy.text(
                                "只有在你使用医院功能并允许定位后，才会使用附近区域查找医院；如果需要启用第三方地图服务，会另行说明并征求同意。",
                                "Your nearby area is used only when you open hospital search and grant location access. Optional third-party map services will be explained and require separate consent before use."
                            )
                        )
                    }
                    .padding(20)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    HStack(spacing: 20) {
                        legalButton(.privacyPolicy)
                        legalButton(.termsOfUse)
                    }

                    Text(LegalCopy.text(
                        "点击“同意并继续”，表示你已阅读并同意《隐私政策》和《用户协议》。高德等可选第三方服务会在实际需要时另行征求同意。",
                        "By tapping Agree and Continue, you confirm that you have read and accepted the Privacy Policy and Terms of Use. Optional third-party services such as AMap will request separate consent only when needed."
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onAgree) {
                        Text("同意并继续")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 54)
                .padding(.bottom, 36)
            }
        }
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document)
        }
    }

    private func legalButton(_ document: LegalDocument) -> some View {
        Button(document.title) {
            legalDocument = document
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(theme.accent)
    }

    private func consentRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(theme.accent)
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

struct AMapPrivacyConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(theme.accentSoft)
                            .frame(width: 72, height: 72)
                        Image(systemName: "map.fill")
                            .font(.system(size: 29, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .frame(maxWidth: .infinity)

                    Text(LegalCopy.text(
                        "为了在中国大陆提供更完整的附近医院结果，爪记可以使用高德地图搜索服务。",
                        "To provide more complete nearby hospital results in mainland China, Zoji can use AMap Search."
                    ))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 14) {
                        amapDisclosureRow(
                            symbol: "location.fill",
                            text: LegalCopy.text(
                                "会向高德发送搜索关键词和附近位置范围，用于返回医院地点信息。",
                                "Search terms and the nearby map area are sent to AMap to return hospital place information."
                            )
                        )
                        amapDisclosureRow(
                            symbol: "cross.case.fill",
                            text: LegalCopy.text(
                                "不会发送宠物资料、健康记录、附件或你的 Zoji 数据。",
                                "Pet profiles, health records, attachments, and other Zoji data are not sent."
                            )
                        )
                        amapDisclosureRow(
                            symbol: "hand.raised.fill",
                            text: LegalCopy.text(
                                "你可以暂不启用；爪记会改用 Apple 地图，但中国大陆的医院结果可能较少。",
                                "You can choose Not Now. Zoji will use Apple Maps instead, though mainland China results may be limited."
                            )
                        )
                    }
                    .padding(18)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Link(
                        LegalCopy.text("查看高德地图开放平台隐私权政策", "View AMap Platform Privacy Policy"),
                        destination: URL(string: "https://lbs.amap.com/pages/privacy/")!
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)

                    Button {
                        onAgree()
                        dismiss()
                    } label: {
                        Text(LegalCopy.text("同意并使用高德", "Agree and Use AMap"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text(LegalCopy.text("暂不启用，使用 Apple 地图", "Not Now — Use Apple Maps"))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle(LegalCopy.text("高德医院搜索", "AMap Hospital Search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LegalCopy.text("关闭", "Close")) {
                        onDecline()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func amapDisclosureRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(theme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    let document: LegalDocument

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(LegalCopy.text("生效日期：2026 年 8 月 14 日", "Effective date: August 14, 2026"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if document == .privacyPolicy {
                    Section(LegalCopy.text("第三方政策", "Third-Party Policies")) {
                        Link(
                            LegalCopy.text("Apple 隐私政策", "Apple Privacy Policy"),
                            destination: URL(string: "https://www.apple.com/legal/privacy/")!
                        )
                        Link(
                            LegalCopy.text("高德地图开放平台隐私权政策", "AMap Platform Privacy Policy"),
                            destination: URL(string: "https://lbs.amap.com/pages/privacy/")!
                        )
                    }
                }

                Section(LegalCopy.text("联系我们", "Contact")) {
                    Link("haoqianglyu@gmail.com", destination: URL(string: "mailto:haoqianglyu@gmail.com")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LegalCopy.text("完成", "Done")) { dismiss() }
                }
            }
        }
    }

    private var sections: [(title: String, body: String)] {
        switch document {
        case .privacyPolicy: privacySections
        case .termsOfUse: termsSections
        }
    }

    private var privacySections: [(String, String)] {
        [
            (
                LegalCopy.text("我们处理的数据", "Data We Process"),
                LegalCopy.text(
                    "爪记用于管理你主动输入的宠物资料、健康记录、提醒、费用、医院收藏及附件。爪记不提供独立账号系统，也不使用这些内容投放广告或进行跨 App 跟踪。",
                    "Zoji manages pet profiles, health records, reminders, expenses, hospital favorites, and attachments that you choose to enter. Zoji does not operate its own account system and does not use this content for advertising or cross-app tracking."
                )
            ),
            (
                LegalCopy.text("本地保存与 iCloud", "Local Storage and iCloud"),
                LegalCopy.text(
                    "数据会先保存在你的设备上。启用 iCloud 后，Apple 可通过你的私有 CloudKit 空间在设备间同步。家庭共享仅会向你选择并邀请的成员共享指定宠物的数据。",
                    "Data is stored on your device first. When iCloud is enabled, Apple may sync it between devices through your private CloudKit storage. Family Sharing shares only the selected pet with members you invite."
                )
            ),
            (
                LegalCopy.text("病例识别", "Medical Record Recognition"),
                LegalCopy.text(
                    "图片文字识别使用 Apple Vision，尽可能在设备上完成。被识别的图片只有在你保存记录时才会作为附件保存。",
                    "Image text recognition uses Apple Vision and is performed on device whenever possible. Recognized images are stored as attachments only when you save the record."
                )
            ),
            (
                LegalCopy.text("位置与地图服务", "Location and Map Services"),
                LegalCopy.text(
                    "只有在你使用医院功能并授权定位时，附近位置范围才会用于搜索。中国大陆可在另行征得同意后使用高德地图搜索；其他地区使用 Apple 地图。地图服务会按各自政策处理查询。爪记不会把宠物或健康数据发送给地图服务。",
                    "The nearby area is used only when you open hospital search and grant location access. In mainland China, AMap Search may be used after separate consent; Apple Maps is used elsewhere. Each map provider processes queries under its own policy. Zoji does not send pet or health data to map providers."
                )
            ),
            (
                LegalCopy.text("保存期限与删除", "Retention and Deletion"),
                LegalCopy.text(
                    "数据会保留到你在 App 中删除、卸载 App 并移除其本地数据，或从 iCloud 删除相应数据为止。共享拥有者可以停止共享，成员也可以离开共享。你可以随时导出完整备份。",
                    "Data remains until you delete it in the app, uninstall the app and remove its local data, or delete the corresponding iCloud data. Share owners can stop sharing and members can leave a share. You can export a complete backup at any time."
                )
            ),
            (
                LegalCopy.text("权限与选择", "Permissions and Choices"),
                LegalCopy.text(
                    "定位和通知权限均为可选，可在 iPhone 系统设置中随时关闭。拒绝高德不会阻止你使用爪记的其他功能；医院页会改用 Apple 地图。",
                    "Location and notification permissions are optional and can be disabled in iPhone Settings at any time. Declining AMap does not block other Zoji features; hospital search will use Apple Maps instead."
                )
            )
        ]
    }

    private var termsSections: [(String, String)] {
        [
            (
                LegalCopy.text("服务用途", "Purpose of the Service"),
                LegalCopy.text(
                    "爪记用于帮助你整理宠物资料、健康记录和提醒，不提供诊断、治疗或紧急医疗服务，也不能替代执业兽医的建议。紧急情况请立即联系兽医或当地急诊机构。",
                    "Zoji helps organize pet profiles, health records, and reminders. It does not provide diagnosis, treatment, or emergency medical services and does not replace advice from a licensed veterinarian. Contact a veterinarian or local emergency provider immediately in an emergency."
                )
            ),
            (
                LegalCopy.text("你的责任", "Your Responsibilities"),
                LegalCopy.text(
                    "你应核对记录、提醒、识别结果和模板是否准确，并遵循药品说明、疫苗记录、当地规定及兽医建议。共享资料前，请确保你有权向受邀成员提供相关内容。",
                    "You are responsible for reviewing records, reminders, recognition results, and templates for accuracy, and for following product instructions, vaccination records, local rules, and veterinary advice. Before sharing, ensure that you have the right to provide the content to invited members."
                )
            ),
            (
                LegalCopy.text("地图与第三方服务", "Maps and Third-Party Services"),
                LegalCopy.text(
                    "医院地点、距离、电话、营业状态和服务范围可能不完整或延迟，请在就诊前直接确认。iCloud、Apple 地图和高德等第三方服务的可用性及数据处理受其各自条款约束。",
                    "Hospital locations, distances, phone numbers, business status, and services may be incomplete or delayed. Confirm directly before visiting. Availability and data handling for third-party services such as iCloud, Apple Maps, and AMap are governed by their respective terms."
                )
            ),
            (
                LegalCopy.text("数据与备份", "Data and Backups"),
                LegalCopy.text(
                    "你应妥善保管导出的备份和附件。虽然爪记采用本地优先保存并支持 iCloud 同步，但网络、设备、Apple 服务或文件损坏仍可能造成服务中断或数据丢失。",
                    "You are responsible for protecting exported backups and attachments. Although Zoji uses local-first storage and supports iCloud sync, network, device, Apple service, or file failures may still interrupt service or cause data loss."
                )
            ),
            (
                LegalCopy.text("协议变更", "Changes to These Terms"),
                LegalCopy.text(
                    "如果服务或数据处理方式发生重要变化，我们会更新本页面及生效日期，并在适当情况下再次征求你的确认。继续使用更新后的服务表示你接受更新后的条款。",
                    "If the service or its data practices materially change, we will update this page and the effective date and request confirmation again when appropriate. Continued use of the updated service means you accept the updated terms."
                )
            )
        ]
    }
}

#Preview {
    AppRootView()
        .environment(AppStore.preview)
        .environment(FamilySharingStore())
}
