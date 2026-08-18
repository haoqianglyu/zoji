import SwiftUI

struct SelectedPetSwitcher: View {
    enum Style: Equatable {
        case avatar
        case capsule
    }

    enum Purpose {
        case selection
        case records
        case reminders

        func accessibilityLabel(for selection: SelectedPet) -> String {
            switch self {
            case .selection:
                return selection.isShared
                    ? String(localized: "切换到家人共享的 \(selection.pet.name)", locale: L10n.locale)
                    : String(localized: "切换到 \(selection.pet.name)", locale: L10n.locale)
            case .records:
                return String(localized: "查看 \(selection.pet.name) 的记录", locale: L10n.locale)
            case .reminders:
                return String(localized: "查看 \(selection.pet.name) 的健康提醒", locale: L10n.locale)
            }
        }
    }

    @Environment(\.appColorTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let pets: [SelectedPet]
    let selectedID: SelectedPet.ID?
    let style: Style
    let purpose: Purpose
    let onSelect: (SelectedPet) -> Void
    var onAdd: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: style == .avatar ? 12 : 10) {
                ForEach(pets) { selection in
                    Button {
                        onSelect(selection)
                    } label: {
                        switch style {
                        case .avatar:
                            avatarLabel(selection)
                        case .capsule:
                            capsuleLabel(selection)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(purpose.accessibilityLabel(for: selection))
                    .accessibilityValue(selection.id == selectedID ? L10n.string("当前") : "")
                }

                if let onAdd, style == .avatar {
                    Button(action: onAdd) {
                        VStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.title3.bold())
                                .foregroundStyle(theme.accent)
                                .frame(width: 48, height: 48)
                                .background(theme.accent.opacity(0.10), in: Circle())
                            Text("添加")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加宠物")
                }
            }
            .padding(.horizontal, style == .avatar ? 2 : 0)
            .padding(.vertical, style == .avatar ? 2 : 0)
        }
    }

    private func avatarLabel(_ selection: SelectedPet) -> some View {
        let isSelected = selection.id == selectedID
        return VStack(spacing: 7) {
            avatar(selection, size: 48, isSelected: isSelected)

            Text(selection.pet.name)
                .font(.caption.weight(isSelected ? .bold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 88 : 62)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func capsuleLabel(_ selection: SelectedPet) -> some View {
        let isSelected = selection.id == selectedID
        return HStack(spacing: 8) {
            avatar(selection, size: 32, isSelected: isSelected)
            Text(selection.pet.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(isSelected ? theme.accent : theme.surfaceMuted, in: Capsule())
    }

    private func avatar(_ selection: SelectedPet, size: CGFloat, isSelected: Bool) -> some View {
        PetAvatarView(
            avatarData: selection.pet.avatarData,
            avatarPresetID: selection.pet.avatarPresetID,
            fallbackSymbol: selection.pet.avatarSymbol,
            size: size,
            background: isSelected ? (style == .avatar ? theme.accent : .white.opacity(0.22)) : theme.accentSoft,
            foreground: isSelected ? .white : theme.accent
        )
        .overlay {
            if style == .avatar {
                Circle()
                    .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2.5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if selection.isShared {
                Image(systemName: "person.2.fill")
                    .font(.system(size: style == .avatar ? 8 : 6, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: style == .avatar ? 18 : 13, height: style == .avatar ? 18 : 13)
                    .background(theme.accent, in: Circle())
                    .overlay { Circle().stroke(theme.surface, lineWidth: style == .avatar ? 2 : 1) }
            }
        }
    }
}

struct HomeView: View {
    private static let scrollTopAnchor = "home-scroll-top"

    @Environment(\.appColorTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @State private var petEditor: PetEditorPresentation?
    @State private var recordEditor: HealthRecordEditorPresentation?
    @State private var reminderEditor: ReminderEditorPresentation?
    @State private var petPendingDeletion: Pet?
    @State private var profileStatusChange: HomePetStatusChange?
    @State private var completingReminderIDs: Set<UUID> = []
    @State private var reminderCompletionMessage: String?
    @State private var reminderCompletionFeedbackTrigger = 0

    private var selectedPet: SelectedPet? { store.selectedPet(using: familyStore) }
    private var selectablePets: [SelectedPet] { store.selectablePets(using: familyStore) }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    Color.clear
                        .frame(height: 1)
                        .id(Self.scrollTopAnchor)
                        .accessibilityHidden(true)

                    if let selectedPet {
                        LazyVStack(spacing: 20) {
                            if store.initialCloudRestorePhase.isVisible {
                                initialCloudRestoreBanner
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            combinedPetSwitcher
                            if selectablePets.count > 1 {
                                crossPetReminderCard
                            }
                            petProfileCard(selectedPet)
                            weightTrendCard(selectedPet)
                            careSummary(for: selectedPet)
                            remindersSection(for: selectedPet)
                            recentRecordsSection(for: selectedPet)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else if store.initialCloudRestorePhase.isVisible {
                        initialCloudRestoreBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        emptyPetState
                            .padding(20)
                            .padding(.top, 54)
                    }
                }
                .refreshable {
                    await store.reloadPersistedAndFamilyData(using: familyStore)
                    // UIRefreshControl restores its own inset first. Once that motion
                    // is almost complete, smoothly settle any stale overscroll left by
                    // the large navigation title instead of snapping it into place.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                            scrollProxy.scrollTo(Self.scrollTopAnchor, anchor: .top)
                        }
                    }
                    // The reload path already starts pending uploads in the background.
                    // Waiting for the entire outbox here can leave the refresh control
                    // pinned when CloudKit is slow or temporarily unavailable.
                }
                .background(theme.background)
                .tint(theme.accent)
                .animation(.easeInOut(duration: 0.22), value: theme)
                .animation(.easeInOut(duration: 0.25), value: store.initialCloudRestorePhase)
            }
            .navigationTitle("爪记 Zoji")
            .sheet(item: $petEditor) { presentation in
                PetEditorView(pet: presentation.pet)
                    .environment(store)
            }
            .sheet(item: $recordEditor) { presentation in
                HealthRecordEditorView(
                    record: presentation.record,
                    initialPetID: presentation.petID,
                    sharedPet: presentation.sharedPet
                )
                    .environment(store)
            }
            .sheet(item: $reminderEditor) { presentation in
                ReminderEditorView(
                    reminder: presentation.reminder,
                    initialPetID: presentation.petID,
                    sharedPet: presentation.sharedPet
                )
                    .environment(store)
            }
            .confirmationDialog(
                profileStatusChange.map { change in
                    change.status == .memorial
                        ? "将 \(change.pet.name) 设为纪念？"
                        : "归档 \(change.pet.name)？"
                } ?? "更改宠物状态",
                isPresented: Binding(
                    get: { profileStatusChange != nil },
                    set: { if !$0 { profileStatusChange = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let change = profileStatusChange {
                    Button(change.status.actionName) {
                        changeProfileStatus(change)
                    }
                }
                Button("取消", role: .cancel) { profileStatusChange = nil }
            } message: {
                Text("健康记录、体重、照片和费用都会保留，但该宠物会退出日常页面，所有系统提醒暂停。")
            }
            .alert(
                "删除 \(petPendingDeletion?.name ?? "这份宠物档案")？",
                isPresented: Binding(
                    get: { petPendingDeletion != nil },
                    set: { if !$0 { petPendingDeletion = nil } }
                )
            ) {
                Button("取消", role: .cancel) { petPendingDeletion = nil }
                Button("删除宠物档案", role: .destructive) {
                    guard let pet = petPendingDeletion else { return }
                    deletePet(pet)
                }
            } message: {
                Text("该宠物的记录和提醒会被删除；如果已开启家庭共享，也会撤销家人访问并删除共享云端副本。")
            }
            .alert("宠物资料操作失败", isPresented: Binding(
                get: { store.petPersistenceMessage != nil },
                set: { if !$0 { store.petPersistenceMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(store.petPersistenceMessage ?? "请稍后再试。")
            }
            .alert("提醒操作失败", isPresented: Binding(
                get: { store.reminderPersistenceMessage != nil },
                set: { if !$0 { store.reminderPersistenceMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(store.reminderPersistenceMessage ?? "请稍后再试。")
            }
            .overlay(alignment: .top) {
                TransientSuccessBanner(message: $reminderCompletionMessage)
            }
            .sensoryFeedback(.success, trigger: reminderCompletionFeedbackTrigger)
        }
    }

    private var initialCloudRestoreBanner: some View {
        let phase = store.initialCloudRestorePhase
        let isDelayed: Bool = {
            if case .delayed = phase { return true }
            return false
        }()

        return ZojiCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.accentSoft)
                        .frame(width: 48, height: 48)

                    if isDelayed {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    } else {
                        ProgressView()
                            .tint(theme.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(isDelayed ? L10n.string("iCloud 同步时间较长") : restoreTitle(for: phase))
                        .font(.headline)

                    Text(restoreDetail(for: phase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isDelayed {
                        Button("重新检查") {
                            NotificationCenter.default.post(
                                name: InitialCloudRestore.retryNotification,
                                object: nil
                            )
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func restoreTitle(for phase: InitialCloudRestorePhase) -> String {
        if case .checking = phase {
            return L10n.string("正在检查 iCloud 资料…")
        }
        return L10n.string("正在从 iCloud 恢复资料…")
    }

    private func restoreDetail(for phase: InitialCloudRestorePhase) -> String {
        if case .delayed = phase {
            return L10n.string("资料会继续在后台恢复，你可以先使用已显示的内容。")
        }

        let count = phase.restoredPetCount
        guard count > 0 else {
            return L10n.string("正在查找宠物档案、健康记录和提醒。")
        }
        return String(
            localized: "已找到 \(count) 只宠物，其他资料会继续同步。",
            locale: L10n.locale
        )
    }

    private var combinedPetSwitcher: some View {
        SelectedPetSwitcher(
            pets: selectablePets,
            selectedID: selectedPet?.id,
            style: .avatar,
            purpose: .selection,
            onSelect: { selection in
                withAnimation(.snappy(duration: 0.28)) {
                    store.select(selection, using: familyStore)
                }
            },
            onAdd: { petEditor = PetEditorPresentation(pet: nil) }
        )
    }

    private var crossPetReminderCard: some View {
        let entries = CrossPetReminderEntry.visibleEntries(from: selectablePets)
        let overdueCount = entries.filter { $0.reminder.isOverdue }.count
        let upcomingCount = entries.count - overdueCount

        return NavigationLink {
            CrossPetReminderOverviewView()
        } label: {
            ZojiCard {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                        .frame(width: 48, height: 48)
                        .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("全部宠物待办")
                            .font(.headline)
                        if entries.isEmpty {
                            Text("未来 7 天暂无安排")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 10) {
                                if overdueCount > 0 {
                                    Label("逾期 \(overdueCount)", systemImage: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                if upcomingCount > 0 {
                                    Label("7 天内 \(upcomingCount)", systemImage: "calendar")
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看全部宠物未来 7 天和已逾期提醒")
    }

    @ViewBuilder
    private func petProfileCard(_ selection: SelectedPet) -> some View {
        if let sharedPet = selection.sharedPet {
            NavigationLink {
                FamilySharedPetDetailView(sharedPet: sharedPet)
            } label: {
                petProfileCardContent(selection, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            petProfileCardContent(selection, showsChevron: false)
        }
    }

    private func petProfileCardContent(_ selection: SelectedPet, showsChevron: Bool) -> some View {
        let pet = selection.pet
        return ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [theme.accent, theme.accentDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 62, y: -72)

            VStack(alignment: .leading, spacing: 18) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        profileAvatar(for: pet)
                        profileIdentity(for: selection)
                    }
                    .padding(.trailing, 48)
                } else {
                    HStack(spacing: 16) {
                        profileAvatar(for: pet)
                        profileIdentity(for: selection)
                        Spacer(minLength: 0)
                    }
                }

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        profileMetricRow(title: "年龄", value: ageText(for: pet))
                        profileMetricRow(title: "体重", value: weightText(for: pet))
                        profileMetricRow(title: "记录", value: recordCountText(selection.records.count))
                    }
                } else {
                    HStack(spacing: 0) {
                        profileMetric(title: "年龄", value: ageText(for: pet))
                        metricDivider
                        profileMetric(title: "体重", value: weightText(for: pet))
                        metricDivider
                        profileMetric(title: "记录", value: recordCountText(selection.records.count))
                    }
                }
            }
            .padding(22)
            .foregroundStyle(.white)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(20)
            } else {
                Menu {
                    Button {
                        petEditor = PetEditorPresentation(pet: pet)
                    } label: {
                        Label("编辑资料", systemImage: "pencil")
                    }

                    Button {
                        profileStatusChange = HomePetStatusChange(pet: pet, status: .archived)
                    } label: {
                        Label("归档宠物", systemImage: "archivebox")
                    }

                    Button {
                        profileStatusChange = HomePetStatusChange(pet: pet, status: .memorial)
                    } label: {
                        Label("设为纪念", systemImage: "heart")
                    }

                    Button(role: .destructive) {
                        petPendingDeletion = pet
                    } label: {
                        Label("删除宠物", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .padding(16)
                .accessibilityLabel("管理 \(pet.name) 的资料")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: theme.accent.opacity(0.18), radius: 18, y: 10)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.20))
            .frame(width: 1, height: 32)
    }

    private func profileAvatar(for pet: Pet) -> some View {
        PetAvatarView(
            avatarData: pet.avatarData,
            avatarPresetID: pet.avatarPresetID,
            fallbackSymbol: pet.avatarSymbol,
            size: 78,
            background: .white.opacity(0.94),
            foreground: theme.accent
        )
        .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 3) }
    }

    private func profileIdentity(for selection: SelectedPet) -> some View {
        let pet = selection.pet
        return VStack(alignment: .leading, spacing: 6) {
            Text(pet.name)
                .font(.system(.title, design: .rounded, weight: .bold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Text(petDescription(pet))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if let sharingLabel = selection.sharingLabel,
               let sharedPet = selection.sharedPet {
                Label(sharingLabel, systemImage: sharedPet.role.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weightTrendCard(_ selection: SelectedPet) -> some View {
        NavigationLink {
            WeightTrendView(
                petID: selection.pet.id,
                sharedPet: selection.sharedPet,
                canEdit: selection.canEdit
            )
        } label: {
            WeightTrendPreviewCard(pet: selection.pet)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看 \(selection.pet.name) 的体重趋势")
    }

    private func profileMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.dynamic(title))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.70))
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }

    private func profileMetricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L10n.dynamic(title))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
            Spacer(minLength: 12)
            Text(value)
                .font(.headline)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func careSummary(for selection: SelectedPet) -> some View {
        if let sharedPet = selection.sharedPet, !selection.canEdit {
            NavigationLink {
                FamilySharedPetDetailView(sharedPet: sharedPet)
            } label: {
                careSummaryCard(for: selection)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看 \(selection.pet.name) 的健康记录")
        } else {
            Button {
                recordEditor = HealthRecordEditorPresentation(
                    record: nil,
                    petID: selection.pet.id,
                    sharedPet: selection.sharedPet
                )
            } label: {
                careSummaryCard(for: selection)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("为 \(selection.pet.name) 添加健康记录")
        }
    }

    private func careSummaryCard(for selection: SelectedPet) -> some View {
        ZojiCard {
            HStack(spacing: 14) {
                Image(systemName: "heart.text.clipboard.fill")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: 48, height: 48)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 4) {
                    Text(careSummaryTitle(for: selection))
                        .font(.headline)
                    Text(careSummaryDetail(for: selection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                Spacer(minLength: 4)

                Image(systemName: selection.canEdit ? "plus.circle.fill" : "eye.fill")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func careSummaryTitle(for selection: SelectedPet) -> String {
        if !selection.canEdit {
            return String(localized: "查看 \(selection.pet.name) 的健康", locale: L10n.locale)
        }
        return selection.reminders.isEmpty
            ? String(localized: "开始记录 \(selection.pet.name) 的健康", locale: L10n.locale)
            : taskSummaryText(for: selection.pet, count: selection.reminders.count)
    }

    private func careSummaryDetail(for selection: SelectedPet) -> String {
        if selection.isShared {
            return selection.canEdit
                ? L10n.string("修改会同步给共享成员。")
                : L10n.string("拥有者授予的是仅查看权限。")
        }
        return selection.reminders.isEmpty
            ? L10n.string("保存疫苗、驱虫、体检或就医经历，建立专属健康时间线。")
            : L10n.string("按时完成照护事项，让每一次健康变化都有迹可循。")
    }

    private func remindersSection(for selection: SelectedPet) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("近期待办")
                    .font(.title3.bold())
                Spacer()
                NavigationLink("管理提醒") {
                    ReminderListView()
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 2)

            if selection.reminders.isEmpty {
                Button {
                    guard selection.canEdit else { return }
                    reminderEditor = ReminderEditorPresentation(
                        reminder: nil,
                        petID: selection.pet.id,
                        sharedPet: selection.sharedPet
                    )
                } label: {
                    emptyContentCard(
                        title: "暂时没有待办",
                        message: "添加疫苗、驱虫、复诊或护理提醒，Zoji 会按时通知你。",
                        symbol: "bell.badge"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!selection.canEdit)
            } else {
                ForEach(selection.reminders.prefix(3)) { reminder in
                    reminderCard(reminder, for: selection)
                }
            }
        }
    }

    private func reminderCard(_ reminder: ReminderItem, for selection: SelectedPet) -> some View {
        let completionLocked = reminder.isCompletionLocked()
        return ZojiCard {
            HStack(spacing: 12) {
                Button {
                    reminderEditor = ReminderEditorPresentation(
                        reminder: reminder,
                        petID: reminder.petID,
                        sharedPet: selection.sharedPet
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: reminder.kind.symbol)
                            .frame(width: 38, height: 38)
                            .foregroundStyle(reminder.isOverdue ? theme.warning : theme.accent)
                            .background((reminder.isOverdue ? theme.warning : theme.accent).opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.dynamic(reminder.title))
                                .font(.headline)
                            Text(reminder.isOverdue ? "\(L10n.string("已逾期")) · \(L10n.date(reminder.dueAt, dateStyle: .abbreviated, timeStyle: .shortened))" : L10n.date(reminder.dueAt, dateStyle: .abbreviated, timeStyle: .shortened))
                                .font(.caption)
                                .foregroundStyle(reminder.isOverdue ? theme.warning : .secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!selection.canEdit)
                .accessibilityLabel("查看提醒详情：\(reminder.title)")

                if selection.canEdit {
                    Button {
                        completeReminder(reminder, for: selection)
                    } label: {
                        if completingReminderIDs.contains(reminder.id) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(completionLocked ? "本期已完成" : "完成")
                        }
                    }
                    .disabled(completingReminderIDs.contains(reminder.id) || completionLocked)
                    .frame(minWidth: 48)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Image(systemName: "eye.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    private func completeReminder(_ reminder: ReminderItem, for selection: SelectedPet) {
        guard !reminder.isCompletionLocked() else { return }
        completingReminderIDs.insert(reminder.id)
        Task {
            defer { completingReminderIDs.remove(reminder.id) }
            do {
                let nextDueAt: Date?
                if let sharedPet = selection.sharedPet {
                    nextDueAt = try await familyStore.completeReminder(reminder, in: sharedPet)
                } else {
                    nextDueAt = try await store.completeReminder(id: reminder.id)
                }
                if let nextDueAt {
                    showReminderCompletion(
                        String(localized: "本次已记录，下次提醒：\(L10n.date(nextDueAt, dateStyle: .long, timeStyle: .shortened))。", locale: L10n.locale)
                    )
                } else {
                    showReminderCompletion(L10n.string("这条一次性提醒已完成，可在健康时间线中查看记录。"))
                }
            } catch {
                store.reminderPersistenceMessage = error.localizedDescription
            }
        }
    }

    private func showReminderCompletion(_ message: String) {
        withAnimation(.snappy(duration: 0.28)) {
            reminderCompletionMessage = message
        }
        reminderCompletionFeedbackTrigger += 1
    }

    private func recentRecordsSection(for selection: SelectedPet) -> some View {
        VStack(spacing: 10) {
            sectionHeader(title: "最近记录", subtitle: selection.isShared ? "共享时间线" : nil)

            if selection.records.isEmpty {
                emptyContentCard(
                    title: "还没有记录",
                    message: "到记录页保存生活照片，或添加疫苗、驱虫、体检和就医信息。",
                    symbol: "list.bullet.clipboard"
                )
            } else {
                ZojiCard {
                    VStack(spacing: 0) {
                        ForEach(Array(selection.records.prefix(3).enumerated()), id: \.element.id) { index, record in
                            NavigationLink {
                                recordDetailDestination(record, for: selection)
                            } label: {
                                recordRow(record)
                            }
                            .buttonStyle(.plain)
                            if index < min(selection.records.count, 3) - 1 {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recordDetailDestination(_ record: HealthRecord, for selection: SelectedPet) -> some View {
        if let sharedPet = selection.sharedPet {
            FamilySharedRecordDetailView(sharedPet: sharedPet, recordID: record.id)
        } else {
            HealthRecordDetailView(recordID: record.id)
        }
    }

    private func sectionHeader(title: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.dynamic(title))
                .font(.title3.bold())
            Spacer()
            if let subtitle {
                Text(L10n.dynamic(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private func emptyContentCard(title: String, message: String, symbol: String) -> some View {
        ZojiCard {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.dynamic(title)).font(.subheadline.bold())
                    Text(L10n.dynamic(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recordRow(_ record: HealthRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.symbol)
                .frame(width: 36, height: 36)
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.dynamic(record.title)).font(.subheadline.weight(.semibold))
                Text(L10n.date(record.occurredAt, dateStyle: .abbreviated, timeStyle: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let cost = record.costCents {
                Text(RegionalFormat.currencyString(minorUnits: cost, code: record.resolvedCurrencyCode))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private var emptyPetState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(theme.accentSoft)
                    .frame(width: 132, height: 132)
                Circle()
                    .stroke(theme.accent.opacity(0.12), lineWidth: 1)
                    .frame(width: 164, height: 164)
                Image(systemName: store.inactivePets.isEmpty ? "pawprint.fill" : "archivebox.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }

            VStack(spacing: 10) {
                Text(store.inactivePets.isEmpty ? "先认识一下你的伙伴" : "日常档案已清空")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(store.inactivePets.isEmpty
                     ? "建立宠物档案后，疫苗、驱虫、体检和就医记录都会整理在它的专属时间线里。"
                     : "归档与纪念资料仍被完整保留，可到“我的 → 宠物档案”中查看或恢复。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Button {
                petEditor = PetEditorPresentation(pet: nil)
            } label: {
                Label("创建宠物档案", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(.white)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func petDescription(_ pet: Pet) -> String {
        [pet.localizedBreed, pet.species.displayName, pet.sex?.displayName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func recordCountText(_ count: Int) -> String {
        String(localized: "\(count) 条", locale: L10n.locale)
    }

    private func taskSummaryText(for pet: Pet, count: Int) -> String {
        String(localized: "\(pet.name) 有 \(count) 项待办", locale: L10n.locale)
    }

    private func ageText(for pet: Pet) -> String {
        guard let birthday = pet.birthday else { return L10n.string("待补充") }
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: Date())
        if let years = components.year, years > 0 {
            return String(localized: "\(years) 岁", locale: L10n.locale)
        }
        if let months = components.month, months > 0 {
            return String(localized: "\(months) 个月", locale: L10n.locale)
        }
        return L10n.string("未满月")
    }

    private func weightText(for pet: Pet) -> String {
        guard let weight = pet.weightKilograms else { return L10n.string("待补充") }
        return RegionalFormat.massString(fromKilograms: weight)
    }

    private func deletePet(_ pet: Pet) {
        Task {
            defer {
                petPendingDeletion = nil
            }
            do {
                try await store.deletePet(id: pet.id)
            } catch {
                store.petPersistenceMessage = error.localizedDescription
            }
        }
    }

    private func changeProfileStatus(_ change: HomePetStatusChange) {
        Task {
            defer { profileStatusChange = nil }
            do {
                try await store.setPetProfileStatus(id: change.pet.id, status: change.status)
            } catch {
                store.petPersistenceMessage = error.localizedDescription
            }
        }
    }
}

private struct HomePetStatusChange: Identifiable {
    let pet: Pet
    let status: PetProfileStatus
    var id: String { "\(pet.id.uuidString)-\(status.rawValue)" }
}

struct CrossPetReminderEntry: Identifiable {
    let selection: SelectedPet
    let reminder: ReminderItem

    var id: String { "\(selection.id)-\(reminder.id.uuidString)" }

    static func visibleEntries(
        from selections: [SelectedPet],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Self] {
        let upperBound = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        return selections
            .flatMap { selection in
                selection.reminders.compactMap { reminder in
                    guard reminder.isEnabled,
                          reminder.dueAt <= upperBound,
                          !reminder.isCompletionLocked(at: now, calendar: calendar) else {
                        return nil
                    }
                    return Self(selection: selection, reminder: reminder)
                }
            }
            .sorted { lhs, rhs in
                if lhs.reminder.isOverdue != rhs.reminder.isOverdue {
                    return lhs.reminder.isOverdue
                }
                return lhs.reminder.dueAt < rhs.reminder.dueAt
            }
    }
}

private struct CrossPetReminderOverviewView: View {
    @Environment(\.appColorTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @State private var completingIDs: Set<UUID> = []
    @State private var operationMessage: String?
    @State private var errorMessage: String?

    private var entries: [CrossPetReminderEntry] {
        CrossPetReminderEntry.visibleEntries(from: store.selectablePets(using: familyStore))
    }

    private var overdue: [CrossPetReminderEntry] {
        entries.filter { $0.reminder.isOverdue }
    }

    private var upcoming: [CrossPetReminderEntry] {
        entries.filter { !$0.reminder.isOverdue }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "未来 7 天暂无待办",
                    systemImage: "checkmark.circle",
                    description: Text("所有日常宠物目前都没有逾期或即将到期的提醒。")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                if !overdue.isEmpty {
                    Section("已逾期") {
                        ForEach(overdue) { entry in
                            reminderRow(entry)
                        }
                    }
                }
                if !upcoming.isEmpty {
                    Section("未来 7 天") {
                        ForEach(upcoming) { entry in
                            reminderRow(entry)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("全部宠物待办")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.reloadPersistedAndFamilyData(using: familyStore)
            await familyStore.synchronizePendingChanges()
        }
        .overlay(alignment: .top) {
            TransientSuccessBanner(message: $operationMessage)
        }
        .alert("无法完成提醒", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private func reminderRow(_ entry: CrossPetReminderEntry) -> some View {
        HStack(spacing: 12) {
            PetAvatarView(
                avatarData: entry.selection.pet.avatarData,
                avatarPresetID: entry.selection.pet.avatarPresetID,
                fallbackSymbol: entry.selection.pet.avatarSymbol,
                size: 42
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.dynamic(entry.reminder.title))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 5) {
                    Text(entry.selection.pet.name)
                    Text("·")
                    Text(L10n.date(entry.reminder.dueAt, dateStyle: .abbreviated, timeStyle: .shortened))
                }
                .font(.caption)
                .foregroundStyle(entry.reminder.isOverdue ? .red : .secondary)
            }

            Spacer(minLength: 6)

            if entry.selection.canEdit {
                Button {
                    complete(entry)
                } label: {
                    if completingIDs.contains(entry.reminder.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("完成")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(completingIDs.contains(entry.reminder.id))
            } else {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("仅查看")
            }
        }
        .padding(.vertical, 4)
    }

    private func complete(_ entry: CrossPetReminderEntry) {
        completingIDs.insert(entry.reminder.id)
        Task {
            defer { completingIDs.remove(entry.reminder.id) }
            do {
                let nextDueAt: Date?
                if let sharedPet = entry.selection.sharedPet {
                    nextDueAt = try await familyStore.completeReminder(entry.reminder, in: sharedPet)
                } else {
                    nextDueAt = try await store.completeReminder(id: entry.reminder.id)
                }
                operationMessage = nextDueAt.map {
                    String(localized: "已完成，下次提醒：\(L10n.date($0, dateStyle: .abbreviated, timeStyle: .shortened))", locale: L10n.locale)
                } ?? L10n.string("这条一次性提醒已完成，可在健康时间线中查看记录。")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PetEditorPresentation: Identifiable {
    let id = UUID()
    let pet: Pet?
}

struct TransientSuccessBanner: View {
    @Environment(\.appColorTheme) private var theme
    @Binding var message: String?

    var body: some View {
        Group {
            if let displayedMessage = message {
                Label(displayedMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(theme.accentDeep, in: Capsule())
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .task(id: message) {
            guard let currentMessage = message else { return }
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled, message == currentMessage else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                message = nil
            }
        }
    }
}

struct ReminderListView: View {
    @Environment(\.appColorTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @State private var editor: ReminderEditorPresentation?
    @State private var reminderPendingDeletion: ReminderItem?
    @State private var completingReminderIDs: Set<UUID> = []
    @State private var completionMessage: String?
    @State private var completionFeedbackTrigger = 0
    @State private var showsCarePlanTemplates = false
    @Binding private var notificationRoute: ReminderNotificationRoute?

    init(notificationRoute: Binding<ReminderNotificationRoute?> = .constant(nil)) {
        _notificationRoute = notificationRoute
    }

    private var selectedPet: SelectedPet? { store.selectedPet(using: familyStore) }
    private var selectablePets: [SelectedPet] { store.selectablePets(using: familyStore) }
    private var activeReminders: [ReminderItem] { selectedPet?.reminders ?? [] }

    var body: some View {
        @Bindable var store = store

        List {
            if selectablePets.count > 1 {
                Section("宠物") {
                    reminderPetSwitcher
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            }

            if selectedPet?.isShared == false {
                Section("快捷计划") {
                Button {
                    showsCarePlanTemplates = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.headline)
                            .foregroundStyle(theme.accent)
                            .frame(width: 40, height: 40)
                            .background(theme.accentSoft, in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("疫苗与驱虫计划模板")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("一次生成多项提醒，可逐项选择")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.activePets.isEmpty)
                }
            }

            if activeReminders.isEmpty {
                ContentUnavailableView {
                    Label("暂无提醒", systemImage: "bell.badge")
                } description: {
                    Text("添加疫苗、驱虫、复诊或日常护理提醒。")
                } actions: {
                    Button("添加提醒") {
                        presentNewReminder()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPet == nil || selectedPet?.canEdit == false)
                }
                .listRowBackground(Color.clear)
            } else {
                let overdue = activeReminders.filter(\.isOverdue)
                let upcoming = activeReminders.filter { !$0.isOverdue }

                if !overdue.isEmpty {
                    reminderSection(title: "已逾期", reminders: overdue)
                }
                if !upcoming.isEmpty {
                    reminderSection(title: "接下来", reminders: upcoming)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("健康提醒")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentNewReminder()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(selectedPet == nil || selectedPet?.canEdit == false)
                .accessibilityLabel("添加提醒")
            }
        }
        .sheet(item: $editor) { presentation in
            ReminderEditorView(
                reminder: presentation.reminder,
                initialPetID: presentation.petID,
                sharedPet: presentation.sharedPet
            )
                .environment(store)
        }
        .sheet(isPresented: $showsCarePlanTemplates) {
            CarePlanTemplatePickerView(initialPetID: store.selectedPetID)
                .environment(store)
        }
        .alert(
            "删除这条提醒？",
            isPresented: Binding(
                get: { reminderPendingDeletion != nil },
                set: { if !$0 { reminderPendingDeletion = nil } }
            )
        ) {
            Button("取消", role: .cancel) { reminderPendingDeletion = nil }
            Button("删除提醒", role: .destructive) {
                guard let reminder = reminderPendingDeletion else { return }
                deleteReminder(reminder)
            }
        }
        .alert("提醒操作失败", isPresented: Binding(
            get: { store.reminderPersistenceMessage != nil },
            set: { if !$0 { store.reminderPersistenceMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(store.reminderPersistenceMessage ?? "请稍后再试。")
        }
        .overlay(alignment: .top) {
            TransientSuccessBanner(message: $completionMessage)
        }
        .sensoryFeedback(.success, trigger: completionFeedbackTrigger)
        .task(id: notificationRoute?.deliveryID) {
            guard let notificationRoute else { return }
            presentNotificationReminder(notificationRoute)
        }
    }

    private func presentNewReminder() {
        editor = ReminderEditorPresentation(
            reminder: nil,
            petID: selectedPet?.pet.id,
            sharedPet: selectedPet?.sharedPet
        )
    }

    private func presentNotificationReminder(_ route: ReminderNotificationRoute) {
        if let reminder = store.reminders.first(where: { $0.id == route.reminderID }) {
            editor = ReminderEditorPresentation(
                reminder: reminder,
                petID: route.petID,
                sharedPet: nil
            )
            return
        }
        for sharedPet in familyStore.sharedPets {
            if let reminder = sharedPet.reminders.first(where: { $0.id == route.reminderID }) {
                editor = ReminderEditorPresentation(
                    reminder: reminder,
                    petID: route.petID,
                    sharedPet: sharedPet
                )
                return
            }
        }
    }

    @ViewBuilder
    private func reminderSection(title: String, reminders: [ReminderItem]) -> some View {
        Section {
            ForEach(reminders) { reminder in
                let completionLocked = reminder.isCompletionLocked()
                HStack(spacing: 12) {
                    Button {
                        editor = ReminderEditorPresentation(
                            reminder: reminder,
                            petID: reminder.petID,
                            sharedPet: selectedPet?.sharedPet
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: reminder.kind.symbol)
                                .font(.headline)
                                .foregroundStyle(reminder.isOverdue ? theme.warning : theme.accent)
                                .frame(width: 40, height: 40)
                                .background(
                                    (reminder.isOverdue ? theme.warning : theme.accent).opacity(0.12),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.dynamic(reminder.title))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminderDateText(reminder.dueAt))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                    if reminder.scheduleType != .oneOff {
                                        Text(ReminderRepeatOption.displayName(for: reminder))
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(reminder.isOverdue ? theme.warning : .secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPet?.canEdit == false)

                    if selectedPet?.canEdit == true {
                        Button {
                            completeReminder(reminder)
                        } label: {
                            if completingReminderIDs.contains(reminder.id) {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(completionLocked ? "已完成" : "完成")
                            }
                        }
                        .disabled(completingReminderIDs.contains(reminder.id) || completionLocked)
                        .frame(minWidth: 48)
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text(completionLocked ? "已完成" : "待办")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if selectedPet?.canEdit == true {
                        Button(role: .destructive) {
                            reminderPendingDeletion = reminder
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text(L10n.dynamic(title))
        }
    }

    private var reminderPetSwitcher: some View {
        SelectedPetSwitcher(
            pets: selectablePets,
            selectedID: selectedPet?.id,
            style: .capsule,
            purpose: .reminders,
            onSelect: { selection in
                withAnimation(.snappy(duration: 0.25)) {
                    store.select(selection, using: familyStore)
                }
            }
        )
    }

    private func reminderDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return date.formatted(
                .dateTime
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
                    .locale(L10n.locale)
            )
        }
        return date.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .locale(L10n.locale)
        )
    }

    private func completeReminder(_ reminder: ReminderItem) {
        guard !reminder.isCompletionLocked() else { return }
        completingReminderIDs.insert(reminder.id)
        Task {
            defer { completingReminderIDs.remove(reminder.id) }
            do {
                let nextDueAt: Date?
                if let sharedPet = selectedPet?.sharedPet {
                    nextDueAt = try await familyStore.completeReminder(reminder, in: sharedPet)
                } else {
                    nextDueAt = try await store.completeReminder(id: reminder.id)
                }
                if let nextDueAt {
                    showCompletion(
                        String(localized: "本次已记录，下次提醒：\(L10n.date(nextDueAt, dateStyle: .long, timeStyle: .shortened))。", locale: L10n.locale)
                    )
                } else {
                    showCompletion(L10n.string("这条一次性提醒已完成，可在健康时间线中查看记录。"))
                }
            } catch {
                store.reminderPersistenceMessage = error.localizedDescription
            }
        }
    }

    private func deleteReminder(_ reminder: ReminderItem) {
        Task {
            defer { reminderPendingDeletion = nil }
            do {
                if let sharedPet = selectedPet?.sharedPet {
                    try await familyStore.deleteReminder(reminder, in: sharedPet)
                } else {
                    try await store.deleteReminder(id: reminder.id)
                }
            } catch {
                store.reminderPersistenceMessage = error.localizedDescription
            }
        }
    }

    private func showCompletion(_ message: String) {
        withAnimation(.snappy(duration: 0.28)) {
            completionMessage = message
        }
        completionFeedbackTrigger += 1
    }
}

private struct CarePlanTemplatePickerView: View {
    @Environment(\.appColorTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss

    @State private var petID: UUID?
    @State private var selectedTemplate: CarePlanTemplate?
    @State private var selectedStepIDs: Set<String> = []
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var notificationTime = Date()
    @State private var isSaving = false
    @State private var resultTitle = ""
    @State private var resultMessage: String?
    @State private var dismissAfterResult = false
    @State private var showsPetSelection = false

    init(initialPetID: UUID?) {
        _petID = State(initialValue: initialPetID)
    }

    private var selectedPet: Pet? {
        store.pets.first { $0.id == petID }
    }

    private var availableTemplates: [CarePlanTemplate] {
        guard let selectedPet else { return [] }
        return CarePlanTemplateCatalog.templates(for: selectedPet.species)
            .sorted { first, second in
                let firstRecommended = CarePlanTemplateCatalog.isRecommended(first, for: selectedPet)
                let secondRecommended = CarePlanTemplateCatalog.isRecommended(second, for: selectedPet)
                return firstRecommended && !secondRecommended
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("计划对象") {
                    Button {
                        showsPetSelection = true
                    } label: {
                        HStack(spacing: 12) {
                            if let selectedPet {
                                PetAvatarView(
                                    avatarData: selectedPet.avatarData,
                                    avatarPresetID: selectedPet.avatarPresetID,
                                    fallbackSymbol: selectedPet.avatarSymbol,
                                    size: 36
                                )
                                Text(selectedPet.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            } else {
                                Label("选择宠物", systemImage: "pawprint")
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let selectedTemplate {
                    templateDetail(selectedTemplate)
                } else if availableTemplates.isEmpty {
                    ContentUnavailableView(
                        "暂无适用模板",
                        systemImage: "pawprint",
                        description: Text("猫狗以外的宠物可以使用右上角加号创建自定义提醒。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("选择模板") {
                        ForEach(availableTemplates) { template in
                            templateButton(template)
                        }
                    }

                    Section {
                        Label("模板只用于安排日程，不代替兽医诊疗。疫苗品种、针数、间隔和驱虫频率请以兽医、产品说明及当地规定为准。", systemImage: "cross.case")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(selectedTemplate == nil ? "照护计划模板" : "确认计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedTemplate == nil {
                        Button("取消") { dismiss() }
                            .disabled(isSaving)
                    } else {
                        Button {
                            withAnimation(.snappy) {
                                self.selectedTemplate = nil
                                selectedStepIDs = []
                            }
                        } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                        .disabled(isSaving)
                    }
                }

                if selectedTemplate != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建计划") { savePlan() }
                            .fontWeight(.semibold)
                            .disabled(isSaving || selectedStepIDs.isEmpty || petID == nil)
                    }
                }
            }
            .onChange(of: petID) { _, _ in
                selectedTemplate = nil
                selectedStepIDs = []
            }
            .sheet(isPresented: $showsPetSelection) {
                CarePlanPetSelectionView(pets: store.activePets, selection: $petID)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(resultTitle, isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("知道了") {
                    if dismissAfterResult {
                        dismiss()
                    }
                }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func templateButton(_ template: CarePlanTemplate) -> some View {
        Button {
            select(template)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.symbol)
                    .font(.headline)
                    .foregroundStyle(theme.accent)
                    .frame(width: 42, height: 42)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(template.localizedTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let selectedPet,
                       CarePlanTemplateCatalog.isRecommended(template, for: selectedPet) {
                        Text("推荐")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.accentSoft, in: Capsule())
                    }
                    Text(template.localizedSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("包含 \(template.steps.count) 项")
                        .font(.caption2)
                        .foregroundStyle(theme.accent)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func templateDetail(_ template: CarePlanTemplate) -> some View {
        Section {
            Label(template.localizedTitle, systemImage: template.symbol)
                .font(.headline)
                .foregroundStyle(theme.accent)
            Text(template.localizedSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DatePicker(
                "首次计划日期",
                selection: $startDate,
                in: Calendar.current.startOfDay(for: Date())...,
                displayedComponents: .date
            )
            DatePicker(
                "提醒时间",
                selection: $notificationTime,
                displayedComponents: .hourAndMinute
            )
        }

        Section("计划项目") {
            ForEach(template.steps) { step in
                Toggle(isOn: Binding(
                    get: { selectedStepIDs.contains(step.id) },
                    set: { isSelected in
                        if isSelected {
                            selectedStepIDs.insert(step.id)
                        } else {
                            selectedStepIDs.remove(step.id)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.localizedTitle)
                            .foregroundStyle(.primary)
                        HStack(spacing: 5) {
                            Text(L10n.date(step.dueDate(from: startDate), dateStyle: .abbreviated, timeStyle: .omitted))
                            if step.scheduleType != .oneOff {
                                Text("·")
                                Text(step.scheduleDescription)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .tint(theme.accent)
            }
        }

        Section {
            Label("模板只用于安排日程，不代替兽医诊疗。疫苗品种、针数、间隔和驱虫频率请以兽医、产品说明及当地规定为准。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func select(_ template: CarePlanTemplate) {
        selectedTemplate = template
        selectedStepIDs = Set(template.steps.map(\.id))
        if let selectedPet {
            startDate = CarePlanTemplateCatalog.suggestedStartDate(for: selectedPet, template: template)
        }
    }

    private func savePlan() {
        guard let petID, let selectedTemplate else { return }
        isSaving = true
        Task {
            do {
                let count = try await store.addCarePlan(
                    petID: petID,
                    template: selectedTemplate,
                    startDate: startDate,
                    notificationTime: notificationTime,
                    selectedStepIDs: selectedStepIDs
                )
                familyStore.selectPrivatePet()
                resultTitle = "计划已创建"
                resultMessage = String(localized: "已添加 \(count) 项健康提醒。之后完成任一提醒时，会自动生成对应的健康记录。", locale: L10n.locale)
                dismissAfterResult = true
            } catch {
                resultTitle = "无法创建计划"
                resultMessage = error.localizedDescription
                dismissAfterResult = false
            }
            isSaving = false
        }
    }
}

private struct CarePlanPetSelectionView: View {
    @Environment(\.appColorTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let pets: [Pet]
    @Binding var selection: UUID?

    var body: some View {
        NavigationStack {
            List(pets) { pet in
                Button {
                    selection = pet.id
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        PetAvatarView(
                            avatarData: pet.avatarData,
                            avatarPresetID: pet.avatarPresetID,
                            fallbackSymbol: pet.avatarSymbol,
                            size: 38
                        )
                        Text(pet.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if selection == pet.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("选择宠物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct ReminderEditorView: View {
    @Environment(\.appColorTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss

    let reminder: ReminderItem?
    private let sharedPet: FamilySharedPet?
    @State private var petID: UUID?
    @State private var title: String
    @State private var kind: RecordKind
    @State private var dueAt: Date
    @State private var repeatOption: ReminderRepeatOption
    @State private var customIntervalDays: String
    @State private var advanceDays: Set<Int>
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(reminder: ReminderItem?, initialPetID: UUID?, sharedPet: FamilySharedPet? = nil) {
        self.reminder = reminder
        self.sharedPet = sharedPet
        _petID = State(initialValue: reminder?.petID ?? initialPetID)
        _title = State(initialValue: reminder?.title ?? RecordKind.vaccine.defaultTitle)
        _kind = State(initialValue: reminder?.kind ?? .vaccine)
        _dueAt = State(initialValue: max(
            reminder?.dueAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!,
            Calendar.current.startOfDay(for: Date())
        ))
        _repeatOption = State(initialValue: reminder.map(ReminderRepeatOption.init(reminder:)) ?? .none)
        _customIntervalDays = State(initialValue: String(
            reminder?.scheduleType == .intervalDays
                ? reminder?.intervalValue ?? 20
                : 20
        ))
        _advanceDays = State(initialValue: Set(reminder?.advanceDays ?? [1, 0]))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒对象") {
                    if let sharedPet {
                        LabeledContent("宠物") {
                            Text(sharedPet.pet.name)
                                .foregroundStyle(.secondary)
                        }
                    } else if reminder?.sourceRecordID != nil {
                        LabeledContent("宠物") {
                            Text(store.pets.first(where: { $0.id == petID })?.name ?? "未知")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("宠物", selection: $petID) {
                            ForEach(store.activePets) { pet in
                                Text(pet.name).tag(Optional(pet.id))
                            }
                        }
                    }
                }

                Section("提醒内容") {
                    Picker("类型", selection: $kind) {
                        ForEach(RecordKind.healthCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    TextField("提醒名称", text: $title)
                    DatePicker(
                        "日期",
                        selection: $dueAt,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )
                }

                Section("重复") {
                    Picker("重复周期", selection: $repeatOption) {
                        ForEach(ReminderRepeatOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    if repeatOption == .customDays {
                        HStack {
                            Text("间隔天数")
                            Spacer()
                            TextField("20", text: $customIntervalDays)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                            Text("天")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("通知时间") {
                    DatePicker(
                        "提醒时间",
                        selection: $dueAt,
                        displayedComponents: .hourAndMinute
                    )
                    ForEach([7, 3, 1, 0], id: \.self) { day in
                        Toggle(day == 0 ? "当天" : "提前 \(day) 天", isOn: Binding(
                            get: { advanceDays.contains(day) },
                            set: { isOn in
                                if isOn {
                                    advanceDays.insert(day)
                                } else {
                                    advanceDays.remove(day)
                                }
                            }
                        ))
                    }
                    Text("系统会在所选时间发送通知。至少选择一个提前日期。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(reminder == nil ? "添加提醒" : "编辑提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(
                            isSaving
                                || petID == nil
                                || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || advanceDays.isEmpty
                                || !isCustomIntervalValid
                        )
                }
            }
            .onChange(of: kind) { oldKind, newKind in
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == oldKind.defaultTitle {
                    title = newKind.defaultTitle
                }
            }
            .alert("无法保存提醒", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "请稍后再试。")
            }
        }
    }

    private func save() {
        guard let petID else { return }
        isSaving = true
        Task {
            do {
                if let sharedPet {
                    let normalizedReminder = ReminderItem(
                        id: reminder?.id ?? UUID(),
                        petID: petID,
                        sourceRecordID: reminder?.sourceRecordID,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        kind: kind,
                        dueAt: dueAt,
                        scheduleType: repeatOption.scheduleType,
                        intervalValue: selectedIntervalValue,
                        advanceDays: Array(advanceDays).sorted(by: >),
                        isEnabled: true,
                        lastCompletedAt: reminder?.lastCompletedAt
                    )
                    try await familyStore.saveReminder(normalizedReminder, in: sharedPet)
                } else if let reminder {
                    try await store.updateReminder(
                        id: reminder.id,
                        petID: petID,
                        title: title,
                        kind: kind,
                        dueAt: dueAt,
                        scheduleType: repeatOption.scheduleType,
                        intervalValue: selectedIntervalValue,
                        advanceDays: Array(advanceDays)
                    )
                    familyStore.selectPrivatePet()
                } else {
                    try await store.addReminder(
                        petID: petID,
                        title: title,
                        kind: kind,
                        dueAt: dueAt,
                        scheduleType: repeatOption.scheduleType,
                        intervalValue: selectedIntervalValue,
                        advanceDays: Array(advanceDays)
                    )
                    familyStore.selectPrivatePet()
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private var selectedIntervalValue: Int? {
        repeatOption == .customDays ? Int(customIntervalDays) : repeatOption.intervalValue
    }

    private var isCustomIntervalValid: Bool {
        guard repeatOption == .customDays else { return true }
        guard let days = Int(customIntervalDays) else { return false }
        return (1 ... 3650).contains(days)
    }
}

struct ReminderEditorPresentation: Identifiable {
    let id = UUID()
    let reminder: ReminderItem?
    let petID: UUID?
    let sharedPet: FamilySharedPet?

    init(reminder: ReminderItem?, petID: UUID?, sharedPet: FamilySharedPet? = nil) {
        self.reminder = reminder
        self.petID = petID
        self.sharedPet = sharedPet
    }
}

enum ReminderRepeatOption: String, CaseIterable, Identifiable {
    case none
    case weekly
    case every30Days
    case customDays
    case monthly
    case quarterly
    case halfYear
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: L10n.string("不重复")
        case .weekly: L10n.string("每周")
        case .every30Days: L10n.string("每 30 天")
        case .customDays: L10n.string("自定义天数")
        case .monthly: L10n.string("每月")
        case .quarterly: L10n.string("每 3 个月")
        case .halfYear: L10n.string("每半年")
        case .yearly: L10n.string("每年")
        }
    }

    var scheduleType: ScheduleType {
        switch self {
        case .none: .oneOff
        case .weekly, .every30Days, .customDays: .intervalDays
        case .monthly, .quarterly, .halfYear: .calendarMonths
        case .yearly: .calendarYears
        }
    }

    var intervalValue: Int? {
        switch self {
        case .none: nil
        case .weekly: 7
        case .every30Days: 30
        case .customDays: nil
        case .monthly: 1
        case .quarterly: 3
        case .halfYear: 6
        case .yearly: 1
        }
    }

    init(reminder: ReminderItem) {
        switch (reminder.scheduleType, reminder.intervalValue) {
        case (.intervalDays, 7): self = .weekly
        case (.intervalDays, 30): self = .every30Days
        case (.intervalDays, _): self = .customDays
        case (.calendarMonths, 1), (.preset, 1): self = .monthly
        case (.calendarMonths, 3), (.preset, 3): self = .quarterly
        case (.calendarMonths, 6), (.preset, 6): self = .halfYear
        case (.calendarYears, 1): self = .yearly
        default: self = .none
        }
    }

    static func displayName(for reminder: ReminderItem) -> String {
        let option = ReminderRepeatOption(reminder: reminder)
        if option == .customDays, let intervalValue = reminder.intervalValue {
            return String(localized: "每 \(intervalValue) 天", locale: L10n.locale)
        }
        return option.displayName
    }
}
