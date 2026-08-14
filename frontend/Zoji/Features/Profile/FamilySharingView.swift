import CoreTransferable
import CloudKit
import SwiftUI
import UniformTypeIdentifiers

struct FamilySharingView: View {
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @State private var ownedSharedPetIDs = Set<UUID>()
    @State private var hasCheckedOwnedShares = false
    @State private var ownedShareCheckTimedOut = false
    @State private var ownedShareCheckDeadline: Task<Void, Never>?
    @State private var preparingInvitationPetID: UUID?
    @State private var preparedInvitation: PreparedFamilyInvitation?
    @State private var invitationError: String?
    @State private var managedPetID: UUID?

    private var memberOverviews: [FamilyMemberOverview] {
        var grouped: [String: FamilyMemberOverview] = [:]
        for sharedPet in familyStore.ownedSharedPets {
            for member in sharedPet.caregivers where member.role != .owner && member.status != .removed {
                let access = FamilyMemberPetAccess(
                    petID: sharedPet.pet.id,
                    petName: sharedPet.pet.name,
                    member: member
                )
                if var overview = grouped[member.personID] {
                    overview.accesses.append(access)
                    grouped[member.personID] = overview
                } else {
                    grouped[member.personID] = FamilyMemberOverview(
                        id: member.personID,
                        displayName: member.displayName,
                        accesses: [access]
                    )
                }
            }
        }
        return grouped.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "person.2.crop.square.stack.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 66, height: 66)
                        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("和家人一起照顾宠物")
                        .font(.title2.bold())

                    Text("可以按宠物邀请家人共同维护资料、健康记录和提醒。邀请时可选择“可更改”或“仅查看”。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }

            Section("共享的内容") {
                sharingContentRow("宠物资料与头像", symbol: "pawprint.fill")
                sharingContentRow("健康记录与病例附件", symbol: "list.bullet.clipboard.fill")
                sharingContentRow("提醒规则与完成记录", symbol: "bell.badge.fill")
            }

            if !familyStore.sharedPets.isEmpty {
                Section {
                    ForEach(familyStore.sharedPets) { sharedPet in
                        NavigationLink {
                            FamilySharedPetDetailView(sharedPet: sharedPet)
                        } label: {
                            HStack(spacing: 13) {
                                PetAvatarView(
                                    avatarData: sharedPet.pet.avatarData,
                                    avatarPresetID: sharedPet.pet.avatarPresetID,
                                    fallbackSymbol: sharedPet.pet.avatarSymbol,
                                    size: 46
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sharedPet.pet.name)
                                        .font(.headline)
                                    Text("家人分享 · \(sharedPet.role.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text("家人分享给我")
                } footer: {
                    Text("共享档案会出现在首页和记录页；有编辑权限时，家人的修改会同步到同一份 iCloud 数据。")
                }
            }

            if !memberOverviews.isEmpty {
                Section {
                    ForEach(memberOverviews) { overview in
                        NavigationLink {
                            FamilyMemberOverviewView(
                                personID: overview.id,
                                fallbackName: L10n.dynamic(overview.displayName)
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 42, height: 42)
                                    .background(AppTheme.accentSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.dynamic(overview.displayName)).font(.headline)
                                    Text(accessiblePetCountText(overview.accesses.count))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("家庭成员")
                } footer: {
                    Text("从成员视角查看每只宠物的独立权限；撤回一只宠物不会影响其他宠物。")
                }
            }

            Section {
                if store.pets.isEmpty {
                    ContentUnavailableView {
                        Label("还没有宠物档案", systemImage: "pawprint")
                    } description: {
                        Text("先添加宠物，之后可以按宠物分别邀请家人。")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.pets) { pet in
                        HStack(spacing: 13) {
                            PetAvatarView(
                                avatarData: pet.avatarData,
                                avatarPresetID: pet.avatarPresetID,
                                fallbackSymbol: pet.avatarSymbol,
                                size: 46
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(pet.name)
                                    .font(.headline)
                                Text(sharingStatusText(for: pet))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if ownedSharedPetIDs.contains(pet.id) {
                                Button {
                                    managedPetID = pet.id
                                } label: {
                                    shareCapsuleLabel(
                                        "管理",
                                        systemImage: "person.2.badge.gearshape.fill"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if ownedShareCheckTimedOut {
                                Button {
                                    Task { await refreshSharingState() }
                                } label: {
                                    shareCapsuleLabel(
                                        "重试",
                                        systemImage: "arrow.clockwise.icloud"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if familyStore.isRefreshing {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("检查中")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            } else if hasCheckedOwnedShares {
                                Menu {
                                    inviteShareLink(for: pet, role: .editor)
                                    inviteShareLink(for: pet, role: .viewer)
                                } label: {
                                    shareCapsuleLabel(
                                        "邀请",
                                        systemImage: "person.badge.plus"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("检查中")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("我分享的宠物")
            } footer: {
                Text(availabilityDetail)
            }

            Section {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.accentSoft, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("发送邀请前选择权限")
                            .font(.subheadline.weight(.semibold))
                        Text("点击“邀请”后，爪记会先让你明确选择“允许一起编辑”或“仅允许查看”，再选择家人。拥有者仍可随时管理成员或停止共享。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("当前权限")
            } footer: {
                Text("完成提醒时使用 CloudKit 原子校验，同一期不会因多人点击而重复生成记录。")
            }

            Section {
                if let syncMessage = familyStore.syncState.message {
                    HStack {
                        Label(L10n.dynamic(syncMessage), systemImage: syncStatusSymbol)
                            .foregroundStyle(syncStatusColor)
                        Spacer()
                        if case .syncing = familyStore.syncState {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                if case .failed = familyStore.syncState {
                    Button {
                        familyStore.retrySync()
                    } label: {
                        Label("重试未同步的修改", systemImage: "arrow.clockwise.icloud")
                    }
                }

                Button {
                    Task { await refreshSharingState() }
                } label: {
                    HStack {
                        Label("刷新共享数据", systemImage: "arrow.clockwise.icloud.fill")
                        Spacer()
                        if familyStore.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(familyStore.isRefreshing)

                if let sharingStatusMessage = familyStore.statusMessage {
                    Text(L10n.dynamic(sharingStatusMessage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !familyStore.recentActivities.isEmpty {
                Section("家庭动态") {
                    ForEach(familyStore.recentActivities.prefix(5)) { activity in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: activity.kind == .joined ? "person.badge.plus" : "person.badge.minus")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.dynamic(activity.message))
                                    .font(.subheadline.weight(activity.isAcknowledged ? .regular : .semibold))
                                Text(L10n.date(activity.occurredAt, dateStyle: .abbreviated, timeStyle: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Label("共享邀请通过 Apple 的私有 CloudKit 完成，爪记不建立公开家庭成员目录，也不需要手机号登录。", systemImage: "lock.icloud.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("家庭共享")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { managedPetID != nil },
            set: { isPresented in
                if !isPresented { managedPetID = nil }
            }
        )) {
            if let managedPetID,
               let pet = store.pets.first(where: { $0.id == managedPetID }) {
                FamilyOwnedPetSharingView(
                    petID: managedPetID,
                    onInvite: { role in
                        prepareInvitation(for: pet, role: role)
                    }
                )
            }
        }
        .overlay {
            if let petID = preparingInvitationPetID,
               let pet = store.pets.first(where: { $0.id == petID }) {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    VStack(spacing: 13) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在准备\(pet.name)的邀请…")
                            .font(.headline)
                        Text("准备完成后才能发送，请稍候")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
        .sheet(item: $preparedInvitation) { invitation in
            PreparedFamilyInvitationView(invitation: invitation)
        }
        .alert("无法准备邀请", isPresented: Binding(
            get: { invitationError != nil },
            set: { if !$0 { invitationError = nil } }
        )) {
            Button("知道了", role: .cancel) { invitationError = nil }
        } message: {
            Text(invitationError ?? "请稍后重试。")
        }
        .task {
            await refreshSharingState()
        }
        .refreshable {
            await refreshSharingState()
        }
        .onDisappear {
            ownedShareCheckDeadline?.cancel()
            ownedShareCheckDeadline = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: FamilySharingService.didAcceptShareNotification)) { notification in
            if let error = notification.userInfo?["error"] as? Error {
                familyStore.statusMessage = String(localized: "接受邀请失败：\(error.localizedDescription)", locale: L10n.locale)
            } else {
                familyStore.statusMessage = L10n.string("家庭邀请已接受，正在读取共享档案。")
                Task { await refreshSharingState() }
            }
        }
    }

    private var availabilityDetail: String {
        if PersistenceController.isCloudKitConfigured {
            return L10n.string("点击“邀请”先选择权限，再从 Apple 的共享面板选择家人。对方只会看到这只宠物。")
        }
        return L10n.string("当前构建未启用 iCloud，只保存到本机。启用 CloudKit 并完成共享联调后，才会出现“邀请家人”按钮。")
    }

    private var syncStatusSymbol: String {
        switch familyStore.syncState {
        case .idle: "checkmark.icloud.fill"
        case .syncing: "arrow.triangle.2.circlepath.icloud.fill"
        case .pending: "clock.badge"
        case .failed: "exclamationmark.icloud.fill"
        }
    }

    private var syncStatusColor: Color {
        if case .failed = familyStore.syncState { return .orange }
        return AppTheme.accent
    }

    private func sharingContentRow(_ title: String, symbol: String) -> some View {
        Label(L10n.dynamic(title), systemImage: symbol)
    }

    private func sharingStatusText(for pet: Pet) -> String {
        if ownedSharedPetIDs.contains(pet.id) { return L10n.string("已开启家庭共享") }
        if ownedShareCheckTimedOut { return L10n.string("iCloud 响应较慢，请重试") }
        if familyStore.isRefreshing { return L10n.string("正在检查共享状态…") }
        return hasCheckedOwnedShares
            ? L10n.string("当前仅自己可见")
            : L10n.string("正在检查共享状态…")
    }

    private func accessiblePetCountText(_ count: Int) -> String {
        if count == 1 {
            return L10n.string("可访问 1 只宠物")
        }
        return String(localized: "可访问 \(count) 只宠物", locale: L10n.locale)
    }

    private func shareCapsuleLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(L10n.dynamic(title))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 104, height: 34)
            .background(AppTheme.accentSoft, in: Capsule())
    }

    @ViewBuilder
    private func inviteShareLink(
        for pet: Pet,
        role: FamilyAccessRole,
        title: String? = nil
    ) -> some View {
        Button {
            prepareInvitation(for: pet, role: role)
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(L10n.dynamic(title ?? (role == .editor ? "允许一起编辑" : "仅允许查看")))
                    Text(L10n.dynamic(role == .editor
                         ? "可修改资料、记录、附件和提醒"
                         : "不能修改或删除任何内容"))
                }
            } icon: {
                Image(systemName: role.symbol)
            }
        }
    }

    private func prepareInvitation(for pet: Pet, role: FamilyAccessRole) {
        guard preparingInvitationPetID == nil else { return }
        preparingInvitationPetID = pet.id
        invitationError = nil
        let sharePayload = payload(for: pet)
        Task {
            do {
                let share = try await FamilySharingService.shared.prepareOrUpdateShare(payload: sharePayload)
                preparedInvitation = PreparedFamilyInvitation(
                    pet: pet,
                    payload: sharePayload,
                    role: role,
                    share: share
                )
            } catch {
                invitationError = error.localizedDescription
            }
            preparingInvitationPetID = nil
        }
    }

    private func payload(for pet: Pet) -> FamilyPetSharePayload {
        FamilyPetSharePayload(
            pet: pet,
            records: store.records,
            reminders: store.reminders
        )
    }

    private func refreshSharingState() async {
        guard PersistenceController.isCloudKitConfigured else { return }
        ownedShareCheckDeadline?.cancel()
        hasCheckedOwnedShares = false
        ownedShareCheckTimedOut = false
        ownedShareCheckDeadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, familyStore.isRefreshing else { return }
            ownedShareCheckTimedOut = true
        }
        defer {
            ownedShareCheckDeadline?.cancel()
            ownedShareCheckDeadline = nil
        }
        if let cachedIDs = try? await FamilySharingLocalStore.shared.ownedPetIDs() {
            ownedSharedPetIDs = cachedIDs.intersection(store.pets.map(\.id))
            hasCheckedOwnedShares = true
        }
        let payloads = store.pets.map(payload(for:))
        await familyStore.refresh(privatePayloads: payloads)
        ownedSharedPetIDs = Set(familyStore.ownedSharedPets.map(\.pet.id))
            .intersection(store.pets.map(\.id))
        hasCheckedOwnedShares = true
        ownedShareCheckTimedOut = false
    }
}

private struct FamilyMemberPetAccess: Identifiable {
    let petID: UUID
    let petName: String
    let member: FamilyShareMember

    var id: String { "\(petID.uuidString)|\(member.id)" }
}

private struct FamilyMemberOverview: Identifiable {
    let id: String
    let displayName: String
    var accesses: [FamilyMemberPetAccess]
}

private extension FamilyShareMember {
    var accessSummary: String {
        status == .accepted
            ? role.displayName
            : "\(role.displayName) · \(status.displayName)"
    }
}

private struct PreparedFamilyInvitation: Identifiable {
    let id = UUID()
    let pet: Pet
    let payload: FamilyPetSharePayload
    let role: FamilyAccessRole
    let share: CKShare
}

private struct PreparedFamilyInvitationView: View {
    let invitation: PreparedFamilyInvitation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                PetAvatarView(
                    avatarData: invitation.pet.avatarData,
                    avatarPresetID: invitation.pet.avatarPresetID,
                    fallbackSymbol: invitation.pet.avatarSymbol,
                    size: 88
                )

                VStack(spacing: 8) {
                    Text("邀请已准备好")
                        .font(.title2.bold())
                    Text("\(invitation.pet.name)的宠物档案")
                        .font(.headline)
                    Label(invitation.role == .editor ? "允许一起编辑" : "仅允许查看",
                          systemImage: invitation.role.symbol)
                        .foregroundStyle(AppTheme.accent)
                }

                Text(invitation.role == .editor
                     ? "对方可以修改宠物资料、健康记录、附件和提醒。"
                     : "对方可以查看档案，但不能修改或删除内容。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ShareLink(
                    item: FamilyPetShareItem(
                        payload: invitation.payload,
                        invitedRole: invitation.role,
                        preparedShare: invitation.share
                    ),
                    preview: SharePreview("\(invitation.pet.name)的宠物档案")
                ) {
                    Label("选择家人并发送", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background)
            .navigationTitle("家庭邀请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct FamilyMemberOverviewView: View {
    let personID: String
    let fallbackName: String

    @Environment(FamilySharingStore.self) private var familyStore
    @State private var pendingRemoval: FamilyMemberPetAccess?
    @State private var showsRemoveAllConfirmation = false
    @State private var updatingAccessID: String?
    @State private var operationMessage: String?

    private var accesses: [FamilyMemberPetAccess] {
        familyStore.ownedSharedPets.flatMap { sharedPet in
            sharedPet.caregivers.compactMap { member in
                guard member.personID == personID,
                      member.role != .owner,
                      member.status != .removed else { return nil }
                return FamilyMemberPetAccess(
                    petID: sharedPet.pet.id,
                    petName: sharedPet.pet.name,
                    member: member
                )
            }
        }.sorted { $0.petName.localizedStandardCompare($1.petName) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 54, height: 54)
                        .background(AppTheme.accentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(accesses.first?.member.displayName ?? fallbackName)
                            .font(.headline)
                        Text("每只宠物分别授权")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("宠物权限") {
                if accesses.isEmpty {
                    ContentUnavailableView(
                        "已无共享权限",
                        systemImage: "person.badge.minus",
                        description: Text("这位成员目前不能访问你的任何宠物。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(accesses) { access in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(access.petName).font(.headline)
                                Text(access.member.accessSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if updatingAccessID == access.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Menu {
                                    Button {
                                        update(access, to: .editor)
                                    } label: {
                                        Label(
                                            "可编辑",
                                            systemImage: access.member.role == .editor
                                                ? "checkmark"
                                                : FamilyAccessRole.editor.symbol
                                        )
                                    }
                                    .disabled(access.member.role == .editor)
                                    Button {
                                        update(access, to: .viewer)
                                    } label: {
                                        Label(
                                            "仅查看",
                                            systemImage: access.member.role == .viewer
                                                ? "checkmark"
                                                : FamilyAccessRole.viewer.symbol
                                        )
                                    }
                                    .disabled(access.member.role == .viewer)
                                    Divider()
                                    Button(role: .destructive) {
                                        pendingRemoval = access
                                    } label: {
                                        Label("撤回\(access.petName)", systemImage: "person.badge.minus")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if !accesses.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showsRemoveAllConfirmation = true
                    } label: {
                        HStack {
                            Label("撤销此成员的全部共享", systemImage: "person.crop.circle.badge.minus")
                            Spacer()
                            if updatingAccessID == "all" {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(updatingAccessID != nil)
                } footer: {
                    Text("会逐只撤回当前列出的宠物，不会删除宠物资料。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("成员权限")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "撤回“\(pendingRemoval?.petName ?? "这只宠物")”？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("只撤回这只宠物", role: .destructive) {
                guard let access = pendingRemoval else { return }
                remove(access)
            }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("该成员对其他宠物的共享和权限保持不变。")
        }
        .alert(
            "撤销此成员的全部共享？",
            isPresented: $showsRemoveAllConfirmation
        ) {
            Button("撤销全部共享", role: .destructive) {
                removeAllAccess()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将撤回对 \(accesses.count) 只宠物的访问；宠物资料和其他成员不受影响。")
        }
        .alert("成员权限", isPresented: Binding(
            get: { operationMessage != nil },
            set: { if !$0 { operationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "操作已完成。")
        }
    }

    private func sharedPet(for access: FamilyMemberPetAccess) -> FamilySharedPet? {
        familyStore.ownedSharedPets.first { $0.pet.id == access.petID }
    }

    private func update(_ access: FamilyMemberPetAccess, to role: FamilyAccessRole) {
        guard let sharedPet = sharedPet(for: access) else { return }
        updatingAccessID = access.id
        Task {
            defer { updatingAccessID = nil }
            do {
                try await familyStore.updatePermission(
                    for: access.member,
                    in: sharedPet,
                    to: role
                )
                operationMessage = String(localized: "已将“\(access.petName)”设为\(role.displayName)。", locale: L10n.locale)
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ access: FamilyMemberPetAccess) {
        guard let sharedPet = sharedPet(for: access) else { return }
        updatingAccessID = access.id
        pendingRemoval = nil
        Task {
            defer { updatingAccessID = nil }
            do {
                try await familyStore.remove(access.member, from: sharedPet)
                operationMessage = String(localized: "已撤回“\(access.petName)”，其他宠物保持不变。", locale: L10n.locale)
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    private func removeAllAccess() {
        let values = accesses
        guard !values.isEmpty else { return }
        updatingAccessID = "all"
        Task {
            defer { updatingAccessID = nil }
            var failures: [String] = []
            for access in values {
                guard let sharedPet = sharedPet(for: access) else {
                    failures.append(access.petName)
                    continue
                }
                do {
                    try await familyStore.remove(access.member, from: sharedPet)
                } catch {
                    failures.append(access.petName)
                }
            }
            operationMessage = failures.isEmpty
                ? "已撤销此成员的全部宠物共享。"
                : "以下宠物暂时撤回失败：\(failures.joined(separator: "、"))。请刷新后重试。"
        }
    }
}

private struct FamilyOwnedPetSharingView: View {
    let petID: UUID
    let onInvite: (FamilyAccessRole) -> Void

    @Environment(FamilySharingStore.self) private var familyStore
    @State private var memberPendingRemoval: FamilyShareMember?
    @State private var isUpdatingMemberID: String?
    @State private var operationMessage: String?

    private var sharedPet: FamilySharedPet? {
        familyStore.ownedSharedPets.first { $0.pet.id == petID }
    }

    private var managedMembers: [FamilyShareMember] {
        sharedPet?.caregivers.filter { $0.role != .owner && $0.status != .removed } ?? []
    }

    var body: some View {
        List {
            if let sharedPet {
                Section {
                    HStack(spacing: 13) {
                        PetAvatarView(
                            avatarData: sharedPet.pet.avatarData,
                            avatarPresetID: sharedPet.pet.avatarPresetID,
                            fallbackSymbol: sharedPet.pet.avatarSymbol,
                            size: 54
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sharedPet.pet.name).font(.headline)
                            Text("每位成员只拥有这只宠物的独立权限")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if managedMembers.isEmpty {
                        ContentUnavailableView(
                            "还没有共同照护者",
                            systemImage: "person.2",
                            description: Text("新增成员后，可在这里单独调整权限或撤回这只宠物。")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(managedMembers) { member in
                            HStack(spacing: 12) {
                                memberAvatar(member)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.dynamic(member.displayName))
                                        .font(.headline)
                                    if let accountIdentifier = member.accountIdentifier {
                                        Text(accountIdentifier)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    Text(member.accessSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isUpdatingMemberID == member.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Menu {
                                        Button {
                                            update(member, to: .editor, in: sharedPet)
                                        } label: {
                                            Label(
                                                "可编辑",
                                                systemImage: member.role == .editor
                                                    ? "checkmark"
                                                    : FamilyAccessRole.editor.symbol
                                            )
                                        }
                                        .disabled(member.role == .editor)

                                        Button {
                                            update(member, to: .viewer, in: sharedPet)
                                        } label: {
                                            Label(
                                                "仅查看",
                                                systemImage: member.role == .viewer
                                                    ? "checkmark"
                                                    : FamilyAccessRole.viewer.symbol
                                            )
                                        }
                                        .disabled(member.role == .viewer)

                                        Divider()
                                        Button(role: .destructive) {
                                            memberPendingRemoval = member
                                        } label: {
                                            Label("撤回这只宠物", systemImage: "person.badge.minus")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                    }
                                    .accessibilityLabel("管理\(L10n.dynamic(member.displayName))")
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text("共同照护者")
                } footer: {
                    Text("邀请接受前，Apple 可能不会提供成员姓名；姓名或账户信息可用后会自动显示。")
                }

                Section("新增成员") {
                    Button { onInvite(.editor) } label: {
                        Label("邀请可编辑成员", systemImage: FamilyAccessRole.editor.symbol)
                    }
                    Button { onInvite(.viewer) } label: {
                        Label("邀请仅查看成员", systemImage: FamilyAccessRole.viewer.symbol)
                    }
                }
            } else {
                ContentUnavailableView(
                    "暂时无法读取共享成员",
                    systemImage: "icloud.slash",
                    description: Text("返回家庭共享页面下拉刷新后再试。")
                )
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("共享成员")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "撤回\(memberPendingRemoval?.displayName ?? "这位成员")对这只宠物的访问？",
            isPresented: Binding(
                get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("撤回这只宠物", role: .destructive) {
                guard let member = memberPendingRemoval, let sharedPet else { return }
                remove(member, from: sharedPet)
            }
            Button("取消", role: .cancel) { memberPendingRemoval = nil }
        } message: {
            Text("只撤回当前这只宠物；该成员对其他宠物的共享不会受到影响。")
        }
        .alert("成员权限", isPresented: Binding(
            get: { operationMessage != nil },
            set: { if !$0 { operationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "操作已完成。")
        }
    }

    private func memberAvatar(_ member: FamilyShareMember) -> some View {
        Image(systemName: member.status == .pending
            ? "person.crop.circle.badge.clock"
            : (member.role == .editor ? "person.crop.circle.badge.checkmark" : "person.crop.circle"))
            .font(.title2)
            .foregroundStyle(AppTheme.accent)
            .frame(width: 42, height: 42)
            .background(AppTheme.accentSoft, in: Circle())
    }

    private func update(_ member: FamilyShareMember, to role: FamilyAccessRole, in sharedPet: FamilySharedPet) {
        isUpdatingMemberID = member.id
        Task {
            defer { isUpdatingMemberID = nil }
            do {
                try await familyStore.updatePermission(for: member, in: sharedPet, to: role)
                operationMessage = String(localized: "已将\(member.displayName)设为“\(role.displayName)”。", locale: L10n.locale)
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ member: FamilyShareMember, from sharedPet: FamilySharedPet) {
        isUpdatingMemberID = member.id
        memberPendingRemoval = nil
        Task {
            defer { isUpdatingMemberID = nil }
            do {
                try await familyStore.remove(member, from: sharedPet)
                operationMessage = String(localized: "已撤回\(member.displayName)对“\(sharedPet.pet.name)”的访问。", locale: L10n.locale)
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }
}

struct FamilySharedPetDetailView: View {
    let sharedPet: FamilySharedPet
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @State private var recordEditor: HealthRecordEditorPresentation?
    @State private var reminderEditor: ReminderEditorPresentation?
    @State private var showsPetEditor = false
    @State private var completingReminderIDs: Set<UUID> = []
    @State private var operationMessage: String?
    @State private var showsLeaveConfirmation = false
    @State private var isLeavingShare = false

    private var currentSharedPet: FamilySharedPet {
        familyStore.sharedPets.first(where: { $0.id == sharedPet.id }) ?? sharedPet
    }

    var body: some View {
        let sharedPet = currentSharedPet
        List {
            Section {
                VStack(spacing: 12) {
                    PetAvatarView(
                        avatarData: sharedPet.pet.avatarData,
                        avatarPresetID: sharedPet.pet.avatarPresetID,
                        fallbackSymbol: sharedPet.pet.avatarSymbol,
                        size: 84
                    )
                    Text(sharedPet.pet.name)
                        .font(.title2.bold())
                    Label("家人共享 · \(sharedPet.role.displayName)", systemImage: sharedPet.role.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.accentSoft, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("基本资料") {
                LabeledContent("类别", value: sharedPet.pet.species.displayName)
                if let breed = sharedPet.pet.localizedBreed, !breed.isEmpty {
                    LabeledContent("品种", value: breed)
                }
                if let sex = sharedPet.pet.sex {
                    LabeledContent("性别", value: sex.displayName)
                }
                if let birthday = sharedPet.pet.birthday {
                    LabeledContent("生日", value: L10n.date(birthday, dateStyle: .long, timeStyle: .omitted))
                }
                if let weight = sharedPet.pet.weightKilograms {
                    LabeledContent("体重", value: RegionalFormat.massString(fromKilograms: weight))
                }
                if sharedPet.canEdit {
                    Button {
                        showsPetEditor = true
                    } label: {
                        Label("编辑宠物资料", systemImage: "pencil")
                    }
                }
            }

            Section {
                if sharedPet.caregivers.isEmpty {
                    Text("Apple 暂未提供其他成员的显示信息。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sharedPet.caregivers.filter { $0.status != .removed }) { member in
                        HStack(spacing: 12) {
                            Image(systemName: member.role == .owner ? "crown.fill" : "person.fill")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.isCurrentUser
                                    ? "\(L10n.dynamic(member.displayName))（我）"
                                    : L10n.dynamic(member.displayName))
                                    .font(.headline)
                                Text(member.accessSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("共同照护者")
            } footer: {
                Text("这里只显示 Apple 为这只宠物提供的成员身份，不展示手机号、邮箱或 Apple ID。")
            }

            Section("健康记录") {
                if sharedPet.records.isEmpty {
                    Text("暂无健康记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sharedPet.records.sorted { $0.occurredAt > $1.occurredAt }) { record in
                        NavigationLink {
                            FamilySharedRecordDetailView(sharedPet: sharedPet, recordID: record.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: record.kind.symbol)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 36, height: 36)
                                    .background(AppTheme.accentSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.dynamic(record.title))
                                        .font(.headline)
                                    Text(L10n.date(record.occurredAt, dateStyle: .abbreviated, timeStyle: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if sharedPet.canEdit {
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await familyStore.deleteHealthRecord(record, in: sharedPet)
                                        } catch {
                                            operationMessage = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    recordEditor = HealthRecordEditorPresentation(record: record, petID: record.petID)
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(AppTheme.accent)
                            }
                        }
                    }
                }
                if sharedPet.canEdit {
                    Button {
                        recordEditor = HealthRecordEditorPresentation(record: nil, petID: sharedPet.pet.id)
                    } label: {
                        Label("添加健康记录", systemImage: "plus")
                    }
                }
            }

            Section("提醒") {
                if sharedPet.reminders.isEmpty {
                    Text("暂无提醒")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sharedPet.reminders.sorted { $0.dueAt < $1.dueAt }) { reminder in
                        HStack(spacing: 12) {
                            Image(systemName: reminder.kind.symbol)
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.dynamic(reminder.title))
                                    .font(.headline)
                                Text(L10n.date(reminder.dueAt, dateStyle: .long, timeStyle: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sharedPet.canEdit, reminder.isEnabled {
                                Button {
                                    complete(reminder, in: sharedPet)
                                } label: {
                                    if completingReminderIDs.contains(reminder.id) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text(reminder.isCompletionLocked() ? "本期已完成" : "完成")
                                    }
                                }
                                .disabled(completingReminderIDs.contains(reminder.id) || reminder.isCompletionLocked())
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text(reminder.isEnabled ? "待办" : "已完成")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard sharedPet.canEdit else { return }
                            reminderEditor = ReminderEditorPresentation(reminder: reminder, petID: reminder.petID)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if sharedPet.canEdit {
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await familyStore.deleteReminder(reminder, in: sharedPet)
                                        } catch {
                                            operationMessage = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                if sharedPet.canEdit {
                    Button {
                        reminderEditor = ReminderEditorPresentation(reminder: nil, petID: sharedPet.pet.id)
                    } label: {
                        Label("添加提醒", systemImage: "plus")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showsLeaveConfirmation = true
                } label: {
                    HStack {
                        Label("退出这只宠物的共享", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                        if isLeavingShare {
                            ProgressView()
                        }
                    }
                }
                .disabled(isLeavingShare)
            } footer: {
                Text("退出后，这只宠物会从你的爪记中移除；不会删除主人保存的宠物资料，也不会影响其他家庭成员。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(sharedPet.pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            try? await familyStore.refresh(sharedPet)
        }
        .sheet(isPresented: $showsPetEditor) {
            PetEditorView(pet: sharedPet.pet, sharedPet: sharedPet)
        }
        .sheet(item: $recordEditor) { presentation in
            HealthRecordEditorView(
                record: presentation.record,
                initialPetID: presentation.petID,
                sharedPet: sharedPet
            )
        }
        .sheet(item: $reminderEditor) { presentation in
            ReminderEditorView(
                reminder: presentation.reminder,
                initialPetID: presentation.petID,
                sharedPet: sharedPet
            )
        }
        .alert(
            "退出“\(sharedPet.pet.name)”的共享？",
            isPresented: $showsLeaveConfirmation
        ) {
            Button("退出共享", role: .destructive) {
                leaveShare(sharedPet)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只会移除你对这只宠物的访问权限，主人和其他家庭成员的数据不受影响。")
        }
        .alert("家庭共享", isPresented: Binding(
            get: { operationMessage != nil },
            set: { if !$0 { operationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(operationMessage ?? "操作已完成。")
        }
    }

    private func complete(_ reminder: ReminderItem, in sharedPet: FamilySharedPet) {
        completingReminderIDs.insert(reminder.id)
        Task {
            defer { completingReminderIDs.remove(reminder.id) }
            do {
                let nextDueAt = try await familyStore.completeReminder(reminder, in: sharedPet)
                operationMessage = nextDueAt.map {
                    String(localized: "本次已记录，下次提醒：\(L10n.date($0, dateStyle: .long, timeStyle: .shortened))。", locale: L10n.locale)
                } ?? "这条一次性提醒已完成并归档。"
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    private func leaveShare(_ sharedPet: FamilySharedPet) {
        isLeavingShare = true
        Task {
            do {
                try await familyStore.leave(sharedPet)
                dismiss()
            } catch {
                isLeavingShare = false
                operationMessage = String(localized: "退出共享失败：\(error.localizedDescription)", locale: L10n.locale)
            }
        }
    }
}

struct FamilySharedRecordDetailView: View {
    let sharedPet: FamilySharedPet
    let recordID: UUID
    @Environment(FamilySharingStore.self) private var familyStore
    @State private var attachmentGallery: HealthRecordAttachmentGalleryPresentation?
    @State private var showsEditor = false

    private var currentSharedPet: FamilySharedPet {
        familyStore.sharedPets.first(where: { $0.id == sharedPet.id }) ?? sharedPet
    }

    private var record: HealthRecord? {
        currentSharedPet.records.first { $0.id == recordID }
    }

    var body: some View {
        Group {
        if let record {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: record.kind.symbol)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 74, height: 74)
                        .background(AppTheme.accentSoft, in: Circle())
                    Text(L10n.dynamic(record.title))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("家人共享 · \(currentSharedPet.role.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section("记录详情") {
                LabeledContent("宠物", value: currentSharedPet.pet.name)
                LabeledContent("类型", value: record.kind.displayName)
                LabeledContent("发生日期", value: L10n.date(record.occurredAt, dateStyle: .long, timeStyle: .omitted))
                if let provider = record.providerName, !provider.isEmpty {
                    LabeledContent("医院/机构", value: provider)
                }
                if let cost = record.costCents {
                    LabeledContent(
                        "费用",
                        value: RegionalFormat.currencyString(minorUnits: cost, code: record.resolvedCurrencyCode)
                    )
                }
            }

            if let notes = record.notes, !notes.isEmpty {
                Section("详情") {
                    Text(notes)
                        .textSelection(.enabled)
                }
            }

            if !record.attachments.isEmpty {
                Section("附件") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                        spacing: 8
                    ) {
                        ForEach(record.attachments) { attachment in
                            attachmentTile(attachment)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("共享记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentSharedPet.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { showsEditor = true }
                }
            }
        }
        .sheet(isPresented: $showsEditor) {
            HealthRecordEditorView(
                record: record,
                initialPetID: currentSharedPet.pet.id,
                sharedPet: currentSharedPet
            )
        }
        .fullScreenCover(item: $attachmentGallery) { presentation in
            HealthRecordAttachmentGallery(
                attachments: presentation.attachments,
                initialAttachmentID: presentation.initialAttachmentID
            )
        }
        } else {
            ContentUnavailableView("记录已删除", systemImage: "trash", description: Text("这条记录可能已被其他家庭成员删除。"))
        }
        }
    }

    private func attachmentTile(_ attachment: HealthRecordAttachment) -> some View {
        Button {
            attachmentGallery = HealthRecordAttachmentGalleryPresentation(
                attachments: record?.attachments ?? [],
                initialAttachmentID: attachment.id
            )
        } label: {
            AppTheme.surfaceMuted
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Group {
                        if attachment.kind == .image,
                           let image = UIImage(data: attachment.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else if attachment.kind == .pdf,
                                  let thumbnail = HealthRecordEditorView.pdfThumbnail(from: attachment.data) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "photo.badge.exclamationmark")
                                .font(.title2)
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .overlay(alignment: .bottomTrailing) {
                    if attachment.kind == .pdf {
                        Image(systemName: "doc.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.58), in: Circle())
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.kind == .pdf ? "查看 PDF" : "放大查看图片")
    }
}

struct DataPrivacyView: View {
    @Environment(AppStore.self) private var store
    @State private var backupDocument: ZojiBackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupMessage: String?
    @State private var backupMessageIsError = false

    var body: some View {
        List {
            Section("数据保存") {
                privacyRow(
                    title: "本地优先",
                    detail: "新增和修改会先写入当前设备，即使暂时没有网络也能使用。",
                    symbol: "iphone"
                )
                privacyRow(
                    title: "私有 iCloud",
                    detail: "启用后由 Apple 在同一 Apple 账号的设备间同步，数据不会进入公开数据库。",
                    symbol: "icloud.fill"
                )
                privacyRow(
                    title: "家庭共享",
                    detail: "只有接受邀请的成员才能访问指定宠物；拥有者可以撤销成员权限。",
                    symbol: "person.2.fill"
                )
            }

            Section("设备能力") {
                privacyRow(
                    title: "通知",
                    detail: "提醒规则可以同步，但每台设备分别创建和管理本地通知。",
                    symbol: "bell.fill"
                )
                privacyRow(
                    title: "病例识别",
                    detail: "图片文字识别优先在设备端通过 Apple Vision 完成。",
                    symbol: "doc.text.viewfinder"
                )
                privacyRow(
                    title: "附近医院",
                    detail: "仅在使用医院功能时，把必要的位置范围交给地图服务查询。",
                    symbol: "location.fill"
                )
            }

            Section {
                Button {
                    backupDocument = ZojiBackupDocument(archive: store.makeBackupArchive())
                    isExportingBackup = true
                } label: {
                    Label("导出完整备份", systemImage: "square.and.arrow.up.fill")
                }
                .disabled(store.pets.isEmpty)

                Button {
                    isImportingBackup = true
                } label: {
                    Label("从文件恢复备份", systemImage: "square.and.arrow.down.fill")
                }
            } header: {
                Text("手动备份")
            } footer: {
                Text("备份包含宠物、健康记录、提醒以及图片/PDF。恢复采用合并方式：相同数据会更新，当前设备独有的数据不会被删除。请妥善保管备份文件。")
            }

        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("数据与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                showBackupMessage("完整备份已导出。", isError: false)
            case .failure(let error):
                showBackupMessage("导出失败：\(error.localizedDescription)", isError: true)
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result {
                    showBackupMessage("无法选择备份：\(error.localizedDescription)", isError: true)
                }
                return
            }
            importBackup(from: url)
        }
        .alert(
            backupMessageIsError ? "备份操作失败" : "备份操作完成",
            isPresented: Binding(
                get: { backupMessage != nil },
                set: { if !$0 { backupMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { backupMessage = nil }
        } message: {
            Text(backupMessage ?? "")
        }
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "爪记完整备份-\(formatter.string(from: Date()))"
    }

    private func importBackup(from url: URL) {
        Task { @MainActor in
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let archive = try ZojiBackupDocument.decode(data)
                try await store.importBackupArchive(archive)
                showBackupMessage(
                    "已合并恢复 \(archive.pets.count) 只宠物、\(archive.records.count) 条记录和 \(archive.reminders.count) 个提醒。",
                    isError: false
                )
            } catch {
                showBackupMessage("恢复失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

    private func showBackupMessage(_ message: String, isError: Bool) {
        backupMessageIsError = isError
        backupMessage = message
    }

    private func privacyRow(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.dynamic(title))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.dynamic(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
