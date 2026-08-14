import CloudKit
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appColorTheme) private var theme
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @AppStorage(AppColorTheme.storageKey) private var colorTheme = AppColorTheme.warm
    @AppStorage(AppUnitSystem.storageKey) private var unitSystem = AppUnitSystem.system
    @State private var isThemePickerPresented = false
    @State private var isUnitPickerPresented = false
    @State private var iCloudStatus = ICloudStorageStatus.checking
    @State private var isRefreshingData = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("本地优先存储").font(.headline)
                            Text("无需注册爪记账号")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("宠物") {
                    LabeledContent("已建立档案") {
                        Text(store.pets.count.formatted(.number.locale(L10n.locale)))
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        PetManagementView()
                            .environment(store)
                    } label: {
                        ProfileSettingLabel("管理宠物档案", systemImage: "slider.horizontal.3")
                    }
                }

                Section {
                    LabeledContent("保存位置") {
                        Text(storageLocationText)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("iCloud 状态") {
                        Text(iCloudStatus.title)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await refreshCloudData() }
                    } label: {
                        HStack {
                            Label("刷新云端数据", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isRefreshingData {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshingData)

                } header: {
                    Text("数据与同步")
                } footer: {
                    Text(iCloudStatus.detail)
                }

                Section {
                    NavigationLink {
                        FamilySharingView()
                            .environment(store)
                    } label: {
                        ProfileSettingLabel("管理家庭共享", systemImage: "person.2.crop.square.stack.fill")
                    }
                    LabeledContent("当前状态") {
                        Text(iCloudStatus.familySharingTitle)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("家庭共享")
                } footer: {
                    Text("共享按宠物管理，只有接受邀请的家人才能查看相应档案。")
                }

                Section {
                    Button {
                        openAppSettings()
                    } label: {
                        HStack {
                            ProfileSettingLabel("语言", systemImage: "globe")
                            Spacer()
                            Text(L10n.currentLanguageDisplayName)
                                .font(.subheadline)
                                .foregroundStyle(theme.accent)
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        isThemePickerPresented = true
                    } label: {
                        HStack {
                            ProfileSettingLabel("配色主题", systemImage: "paintpalette.fill")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 11, height: 11)
                                Text(colorTheme.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.accent)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(AppAppearance.allCases) { option in
                            Button {
                                appearance = option
                            } label: {
                                if appearance == option {
                                    Label(option.displayName, systemImage: "checkmark")
                                } else {
                                    Text(option.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            ProfileSettingLabel("显示模式", systemImage: appearance.systemImage)
                            Spacer()
                            Text(appearance.displayName)
                                .font(.subheadline)
                                .foregroundStyle(theme.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        isUnitPickerPresented = true
                    } label: {
                        HStack {
                            ProfileSettingLabel("单位", systemImage: "ruler")
                            Spacer()
                            Text(unitSystem.displayName)
                                .font(.subheadline)
                                .foregroundStyle(theme.accent)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(unitSystem)
                } header: {
                    Text("语言与外观")
                } footer: {
                    Text("语言默认跟随 iPhone；单位可跟随地区，也可单独选择公制或美制。")
                }

                Section("权限与隐私") {
                    Button {
                        openAppSettings()
                    } label: {
                        HStack {
                            ProfileSettingLabel("通知与定位设置", systemImage: "gearshape.fill")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DataPrivacyView()
                    } label: {
                        ProfileSettingLabel("数据与隐私", systemImage: "hand.raised.fill")
                    }
                }

                Section {
                    Text("健康周期模板仅用于提高录入效率，请以接种凭证、产品说明或兽医建议为准。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .tint(theme.accent)
            .animation(.easeInOut(duration: 0.22), value: theme)
            .navigationTitle("我的")
            .sheet(isPresented: $isThemePickerPresented) {
                ColorThemePickerSheet(selection: $colorTheme)
            }
            .sheet(isPresented: $isUnitPickerPresented) {
                UnitSystemPickerSheet(selection: $unitSystem)
            }
            .task {
                await updateICloudStatus()
            }
        }
    }

    private func refreshCloudData() async {
        isRefreshingData = true
        defer { isRefreshingData = false }
        await updateICloudStatus()
        await store.reloadPersistedData()
    }

    private var storageLocationText: String {
        PersistenceController.isCloudKitConfigured
            ? L10n.string("本机 + 私有 iCloud")
            : L10n.string("仅本机")
    }

    private func updateICloudStatus() async {
        guard PersistenceController.isCloudKitConfigured else {
            iCloudStatus = .developmentLocalOnly
            return
        }
        do {
            let status = try await CKContainer(
                identifier: PersistenceController.cloudKitContainerIdentifier
            ).accountStatus()
            iCloudStatus = ICloudStorageStatus(status)
        } catch {
            iCloudStatus = .temporarilyUnavailable
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct UnitSystemPickerSheet: View {
    @Binding var selection: AppUnitSystem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ForEach(AppUnitSystem.allCases) { option in
                    Button {
                        selection = option
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 40, height: 40)
                                .background(theme.accentSoft, in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(option.detailText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selection == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(theme.accent)
                            } else {
                                Image(systemName: "circle")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(
                            selection == option ? theme.accentSoft : theme.surface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    selection == option
                                        ? theme.accent.opacity(0.45)
                                        : Color.secondary.opacity(0.10)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(theme.background)
            .navigationTitle("单位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(350)])
        .presentationDragIndicator(.visible)
    }
}

private struct ColorThemePickerSheet: View {
    @Binding var selection: AppColorTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var currentTheme

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppColorTheme.allCases) { theme in
                        Button {
                            selection = theme
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: theme.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 34, height: 34)
                                    .background(theme.accentSoft, in: Circle())

                                Text(theme.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .layoutPriority(1)

                                Spacer(minLength: 4)

                                if selection == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .padding(.horizontal, 13)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(
                                selection == theme ? theme.accentSoft : currentTheme.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(selection == theme ? theme.accent.opacity(0.45) : Color.secondary.opacity(0.10))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selection == theme ? L10n.string("已选择") : "")
                    }
                }
                .padding(20)
            }
            .background(currentTheme.background)
            .navigationTitle("配色主题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .tint(selection.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ProfileSettingLabel: View {
    @Environment(\.appColorTheme) private var theme
    private let title: LocalizedStringKey
    private let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.accent)
        }
    }
}

private enum ICloudStorageStatus {
    case checking
    case developmentLocalOnly
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .couldNotDetermine, .temporarilyUnavailable: self = .temporarilyUnavailable
        @unknown default: self = .temporarilyUnavailable
        }
    }

    var title: String {
        switch self {
        case .checking: L10n.string("检查中…")
        case .developmentLocalOnly: L10n.string("开发版仅本机")
        case .available: L10n.string("已开启")
        case .noAccount: L10n.string("未登录")
        case .restricted: L10n.string("受系统限制")
        case .temporarilyUnavailable: L10n.string("暂时不可用")
        }
    }

    var detail: String {
        switch self {
        case .checking: L10n.string("正在检查 iCloud 状态，本机数据不受影响。")
        case .developmentLocalOnly: L10n.string("当前构建未启用 iCloud，数据仅保存在本机。")
        case .available: L10n.string("数据先保存在本机，系统会自动同步到你的私有 iCloud 空间。")
        case .noAccount: L10n.string("当前仅保存在本机。登录 iCloud 后，系统会自动开始同步。")
        case .restricted: L10n.string("当前设备限制了 iCloud；数据仍会保存在本机。")
        case .temporarilyUnavailable: L10n.string("暂时无法连接 iCloud；数据会保存在本机并在服务恢复后同步。")
        }
    }

    var familySharingTitle: String {
        switch self {
        case .checking: L10n.string("检查中…")
        case .available: L10n.string("可用")
        case .noAccount: L10n.string("需要登录 iCloud")
        case .developmentLocalOnly, .restricted, .temporarilyUnavailable: L10n.string("不可用")
        }
    }
}

private struct PetManagementView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appColorTheme) private var theme
    @State private var isAddingPet = false
    @State private var editingPet: Pet?
    @State private var petPendingDeletion: Pet?

    var body: some View {
        List {
            if store.pets.isEmpty {
                ContentUnavailableView {
                    Label("还没有宠物档案", systemImage: "pawprint")
                } description: {
                    Text("添加第一只宠物，开始整理它的健康资料。")
                } actions: {
                    Button("添加宠物") { isAddingPet = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.pets) { pet in
                        Button {
                            store.selectedPetID = pet.id
                            editingPet = pet
                        } label: {
                            HStack(spacing: 14) {
                                PetAvatarView(
                                    avatarData: pet.avatarData,
                                    avatarPresetID: pet.avatarPresetID,
                                    fallbackSymbol: pet.avatarSymbol,
                                    size: 44
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(pet.name)
                                            .font(.headline)
                                        if store.selectedPetID == pet.id {
                                            Text("当前")
                                                .font(.caption2.bold())
                                                .foregroundStyle(theme.accent)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(theme.accent.opacity(0.10), in: Capsule())
                                        }
                                    }
                                    Text([pet.localizedBreed, pet.species.displayName].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
                                petPendingDeletion = pet
                            }
                            Button("编辑") { editingPet = pet }
                                .tint(theme.accent)
                        }
                    }
                } footer: {
                    Text("点击宠物可以编辑资料；首页可切换当前查看的宠物。")
                }
            }
        }
        .navigationTitle("宠物档案")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingPet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加宠物")
            }
        }
        .sheet(isPresented: $isAddingPet) {
            PetEditorView()
                .environment(store)
        }
        .sheet(item: $editingPet) { pet in
            PetEditorView(pet: pet)
                .environment(store)
        }
        .confirmationDialog(
            "删除 \(petPendingDeletion?.name ?? "这份宠物档案")？",
            isPresented: Binding(
                get: { petPendingDeletion != nil },
                set: { if !$0 { petPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除宠物档案", role: .destructive) {
                guard let pet = petPendingDeletion else { return }
                Task {
                    do {
                        try await store.deletePet(id: pet.id)
                    } catch {
                        store.petPersistenceMessage = error.localizedDescription
                    }
                    petPendingDeletion = nil
                }
            }
            Button("取消", role: .cancel) { petPendingDeletion = nil }
        }
        .alert("宠物资料操作失败", isPresented: Binding(
            get: { store.petPersistenceMessage != nil },
            set: { if !$0 { store.petPersistenceMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(store.petPersistenceMessage ?? "请稍后再试。")
        }
    }
}
