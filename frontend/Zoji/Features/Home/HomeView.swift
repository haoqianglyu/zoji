import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @AppStorage(AppColorTheme.storageKey) private var colorTheme = AppColorTheme.warm
    @State private var petEditor: PetEditorPresentation?
    @State private var recordEditor: HealthRecordEditorPresentation?
    @State private var reminderEditor: ReminderEditorPresentation?
    @State private var petPendingDeletion: Pet?
    @State private var completingReminderIDs: Set<UUID> = []
    @State private var reminderCompletionMessage: String?

    private var selectedSharedPet: FamilySharedPet? { familyStore.selectedSharedPet }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                if let sharedPet = selectedSharedPet {
                    LazyVStack(spacing: 20) {
                        combinedPetSwitcher
                        sharedPetProfileCard(sharedPet)
                        sharedWeightTrendCard(sharedPet)
                        sharedCareSummary(sharedPet)
                        sharedRemindersSection(sharedPet)
                        sharedRecentRecordsSection(sharedPet)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else if let pet = store.selectedPet {
                    LazyVStack(spacing: 20) {
                        combinedPetSwitcher
                        petProfileCard(pet)
                        weightTrendCard(pet)
                        careSummary(for: pet)
                        remindersSection
                        recentRecordsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else {
                    emptyPetState
                        .padding(20)
                        .padding(.top, 54)
                }
            }
            .refreshable {
                await store.reloadPersistedAndFamilyData(using: familyStore)
                await familyStore.synchronizePendingChanges()
            }
            .background(colorTheme.background)
            .tint(colorTheme.accent)
            .animation(.easeInOut(duration: 0.22), value: colorTheme)
            .navigationTitle("爪记 Zoji")
            .sheet(item: $petEditor) { presentation in
                PetEditorView(pet: presentation.pet)
                    .environment(store)
            }
            .sheet(item: $recordEditor) { presentation in
                HealthRecordEditorView(
                    record: presentation.record,
                    initialPetID: presentation.petID,
                    sharedPet: familyStore.selectedSharedPet
                )
                    .environment(store)
            }
            .sheet(item: $reminderEditor) { presentation in
                ReminderEditorView(
                    reminder: presentation.reminder,
                    initialPetID: presentation.petID,
                    sharedPet: familyStore.selectedSharedPet
                )
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
                    deletePet(pet)
                }
                Button("取消", role: .cancel) { petPendingDeletion = nil }
            } message: {
                Text("该宠物在本机的记录和提醒也会从当前界面移除。")
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
            .alert("系统通知未开启", isPresented: Binding(
                get: { store.notificationPermissionMessage != nil },
                set: { if !$0 { store.notificationPermissionMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(store.notificationPermissionMessage ?? "提醒仍会保存在 App 中。")
            }
            .alert("提醒已完成", isPresented: Binding(
                get: { reminderCompletionMessage != nil },
                set: { if !$0 { reminderCompletionMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(reminderCompletionMessage ?? "已更新待办。")
            }
        }
    }

    private var combinedPetSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.pets) { pet in
                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
                            familyStore.selectPrivatePet()
                            store.selectedPetID = pet.id
                        }
                    } label: {
                        VStack(spacing: 7) {
                            PetAvatarView(
                                avatarData: pet.avatarData,
                                avatarPresetID: pet.avatarPresetID,
                                fallbackSymbol: pet.avatarSymbol,
                                size: 48,
                                background: familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id
                                    ? AppTheme.accent
                                    : AppTheme.surfaceMuted,
                                foreground: familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id ? .white : AppTheme.accent
                            )
                            .overlay {
                                Circle()
                                    .stroke(familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id ? AppTheme.accent : .clear, lineWidth: 2.5)
                            }

                            Text(pet.name)
                                .font(.caption.weight(familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id ? .bold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: 62)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换到 \(pet.name)")
                }

                ForEach(familyStore.sharedPets) { sharedPet in
                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
                            familyStore.selectedSharedPetID = sharedPet.id
                        }
                    } label: {
                        VStack(spacing: 7) {
                            PetAvatarView(
                                avatarData: sharedPet.pet.avatarData,
                                avatarPresetID: sharedPet.pet.avatarPresetID,
                                fallbackSymbol: sharedPet.pet.avatarSymbol,
                                size: 48,
                                background: familyStore.selectedSharedPetID == sharedPet.id ? AppTheme.accent : AppTheme.surfaceMuted,
                                foreground: familyStore.selectedSharedPetID == sharedPet.id ? .white : AppTheme.accent
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(AppTheme.accent, in: Circle())
                                    .overlay { Circle().stroke(AppTheme.surface, lineWidth: 2) }
                            }
                            Text(sharedPet.pet.name)
                                .font(.caption.weight(familyStore.selectedSharedPetID == sharedPet.id ? .bold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: 62)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换到家人共享的 \(sharedPet.pet.name)")
                }

                Button {
                    petEditor = PetEditorPresentation(pet: nil)
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.accent.opacity(0.10), in: Circle())
                        Text("添加")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }

    private func sharedPetProfileCard(_ sharedPet: FamilySharedPet) -> some View {
        NavigationLink {
            FamilySharedPetDetailView(sharedPet: sharedPet)
        } label: {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [colorTheme.accent, colorTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.08)).frame(width: 180, height: 180).offset(x: 62, y: -72)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        PetAvatarView(
                            avatarData: sharedPet.pet.avatarData,
                            avatarPresetID: sharedPet.pet.avatarPresetID,
                            fallbackSymbol: sharedPet.pet.avatarSymbol,
                            size: 78,
                            background: .white.opacity(0.94),
                            foreground: AppTheme.accent
                        )
                        .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 3) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sharedPet.pet.name).font(.system(size: 28, weight: .bold, design: .rounded)).lineLimit(1)
                            Text(petDescription(sharedPet.pet)).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                            Label("家庭共享 · \(sharedPet.role.displayName)", systemImage: sharedPet.role.symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 0) {
                        profileMetric(title: "年龄", value: ageText(for: sharedPet.pet))
                        metricDivider
                        profileMetric(title: "体重", value: weightText(for: sharedPet.pet))
                        metricDivider
                        profileMetric(title: "健康记录", value: recordCountText(sharedPet.records.count))
                    }
                }
                .padding(22)
                .foregroundStyle(.white)
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8)).padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sharedCareSummary(_ sharedPet: FamilySharedPet) -> some View {
        Button {
            guard sharedPet.canEdit else { return }
            recordEditor = HealthRecordEditorPresentation(record: nil, petID: sharedPet.pet.id)
        } label: {
            ZojiCard {
                HStack(spacing: 14) {
                    Image(systemName: "heart.text.clipboard.fill").font(.title2).foregroundStyle(AppTheme.accent)
                        .frame(width: 48, height: 48).background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sharedPet.canEdit ? "记录 \(sharedPet.pet.name) 的健康" : "查看 \(sharedPet.pet.name) 的健康")
                            .font(.headline)
                        Text(sharedPet.canEdit ? "修改会同步给共享成员。" : "拥有者授予的是仅查看权限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: sharedPet.canEdit ? "plus.circle.fill" : "eye.fill").font(.title2).foregroundStyle(AppTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sharedWeightTrendCard(_ sharedPet: FamilySharedPet) -> some View {
        NavigationLink {
            WeightTrendView(
                petID: sharedPet.pet.id,
                readOnlyPet: sharedPet.pet,
                canEdit: false
            )
        } label: {
            WeightTrendPreviewCard(pet: sharedPet.pet)
        }
        .buttonStyle(.plain)
    }

    private func sharedRemindersSection(_ sharedPet: FamilySharedPet) -> some View {
        VStack(spacing: 10) {
            sectionHeader(title: "近期待办", subtitle: "家庭共享")
            let reminders = sharedPet.reminders.filter(\.isEnabled).sorted { $0.dueAt < $1.dueAt }
            if reminders.isEmpty {
                emptyContentCard(title: "暂时没有待办", message: "可在共享档案详情中添加提醒。", symbol: "bell.badge")
            } else {
                ForEach(reminders.prefix(3)) { reminder in
                    ZojiCard {
                        HStack(spacing: 12) {
                            Button {
                                reminderEditor = ReminderEditorPresentation(
                                    reminder: reminder,
                                    petID: sharedPet.pet.id
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: reminder.kind.symbol)
                                        .frame(width: 38, height: 38)
                                        .foregroundStyle(AppTheme.accent)
                                        .background(AppTheme.accentSoft, in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(L10n.dynamic(reminder.title)).font(.headline)
                                        Text(L10n.date(reminder.dueAt, dateStyle: .abbreviated, timeStyle: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看提醒详情：\(reminder.title)")

                            if sharedPet.canEdit {
                                Button(reminder.isCompletionLocked() ? "本期已完成" : "完成") {
                                    completeSharedReminder(reminder, in: sharedPet)
                                }
                                .disabled(completingReminderIDs.contains(reminder.id) || reminder.isCompletionLocked())
                                .buttonStyle(.bordered).controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sharedRecentRecordsSection(_ sharedPet: FamilySharedPet) -> some View {
        VStack(spacing: 10) {
            sectionHeader(title: "最近记录", subtitle: "共享时间线")
            if sharedPet.records.isEmpty {
                emptyContentCard(title: "还没有健康记录", message: "可在共享档案中添加第一条记录。", symbol: "list.bullet.clipboard")
            } else {
                ZojiCard {
                    VStack(spacing: 0) {
                        ForEach(Array(sharedPet.records.sorted { $0.occurredAt > $1.occurredAt }.prefix(3).enumerated()), id: \.element.id) { index, record in
                            NavigationLink {
                                FamilySharedRecordDetailView(sharedPet: sharedPet, recordID: record.id)
                            } label: { recordRow(record) }
                            .buttonStyle(.plain)
                            if index < min(sharedPet.records.count, 3) - 1 { Divider().padding(.leading, 50) }
                        }
                    }
                }
            }
        }
    }

    private func completeSharedReminder(_ reminder: ReminderItem, in sharedPet: FamilySharedPet) {
        completingReminderIDs.insert(reminder.id)
        Task {
            defer { completingReminderIDs.remove(reminder.id) }
            do {
                let next = try await familyStore.completeReminder(reminder, in: sharedPet)
                reminderCompletionMessage = next.map { String(localized: "本次已记录，下次提醒：\(L10n.date($0, dateStyle: .long, timeStyle: .shortened))。", locale: L10n.locale) }
                    ?? "这条一次性提醒已完成并归档。"
            } catch {
                store.reminderPersistenceMessage = error.localizedDescription
            }
        }
    }

    private func petProfileCard(_ pet: Pet) -> some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [colorTheme.accent, colorTheme.accentDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 62, y: -72)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    PetAvatarView(
                        avatarData: pet.avatarData,
                        avatarPresetID: pet.avatarPresetID,
                        fallbackSymbol: pet.avatarSymbol,
                        size: 78,
                        background: .white.opacity(0.94),
                        foreground: AppTheme.accent
                    )
                    .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 3) }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(pet.name)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .lineLimit(1)

                        Text(petDescription(pet))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    profileMetric(title: "年龄", value: ageText(for: pet))
                    metricDivider
                    profileMetric(title: "体重", value: weightText(for: pet))
                    metricDivider
                    profileMetric(title: "健康记录", value: recordCountText(store.selectedRecords.count))
                }
            }
            .padding(22)
            .foregroundStyle(.white)

            Menu {
                Button {
                    petEditor = PetEditorPresentation(pet: pet)
                } label: {
                    Label("编辑资料", systemImage: "pencil")
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
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.accent.opacity(0.18), radius: 18, y: 10)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.20))
            .frame(width: 1, height: 32)
    }

    private func weightTrendCard(_ pet: Pet) -> some View {
        NavigationLink {
            WeightTrendView(petID: pet.id)
        } label: {
            WeightTrendPreviewCard(pet: pet)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看 \(pet.name) 的体重趋势")
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

    private func careSummary(for pet: Pet) -> some View {
        Button {
            recordEditor = HealthRecordEditorPresentation(record: nil, petID: pet.id)
        } label: {
            ZojiCard {
                HStack(spacing: 14) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.selectedReminders.isEmpty ? "开始记录 \(pet.name) 的健康" : taskSummaryText(for: pet, count: store.selectedReminders.count))
                            .font(.headline)
                        Text(store.selectedReminders.isEmpty ? "保存疫苗、驱虫、体检或就医经历，建立专属健康时间线。" : "按时完成照护事项，让每一次健康变化都有迹可循。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("为 \(pet.name) 添加健康记录")
    }

    private var remindersSection: some View {
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

            if store.selectedReminders.isEmpty {
                Button {
                    reminderEditor = ReminderEditorPresentation(reminder: nil, petID: store.selectedPetID)
                } label: {
                    emptyContentCard(
                        title: "暂时没有待办",
                        message: "添加疫苗、驱虫、复诊或护理提醒，Zoji 会按时通知你。",
                        symbol: "bell.badge"
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(store.selectedReminders.prefix(3)) { reminder in
                    reminderCard(reminder)
                }
            }
        }
    }

    private func reminderCard(_ reminder: ReminderItem) -> some View {
        let completionLocked = reminder.isCompletionLocked()
        return ZojiCard {
            HStack(spacing: 12) {
                Button {
                    reminderEditor = ReminderEditorPresentation(
                        reminder: reminder,
                        petID: reminder.petID
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: reminder.kind.symbol)
                            .frame(width: 38, height: 38)
                            .foregroundStyle(reminder.isOverdue ? AppTheme.warning : AppTheme.accent)
                            .background((reminder.isOverdue ? AppTheme.warning : AppTheme.accent).opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.dynamic(reminder.title))
                                .font(.headline)
                            Text(reminder.isOverdue ? "\(L10n.string("已逾期")) · \(L10n.date(reminder.dueAt, dateStyle: .abbreviated, timeStyle: .shortened))" : L10n.date(reminder.dueAt, dateStyle: .abbreviated, timeStyle: .shortened))
                                .font(.caption)
                                .foregroundStyle(reminder.isOverdue ? AppTheme.warning : .secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看提醒详情：\(reminder.title)")

                Button {
                    completeReminder(reminder)
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
            }
        }
    }

    private func completeReminder(_ reminder: ReminderItem) {
        guard !reminder.isCompletionLocked() else { return }
        completingReminderIDs.insert(reminder.id)
        Task {
            defer { completingReminderIDs.remove(reminder.id) }
            do {
                let nextDueAt = try await store.completeReminder(id: reminder.id)
                if let nextDueAt {
                    reminderCompletionMessage = String(localized: "本次已记录，下次提醒：\(L10n.date(nextDueAt, dateStyle: .long, timeStyle: .shortened))。", locale: L10n.locale)
                } else {
                    reminderCompletionMessage = L10n.string("这条一次性提醒已完成并归档。")
                }
            } catch {
                store.reminderPersistenceMessage = error.localizedDescription
            }
        }
    }

    private var recentRecordsSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "最近记录")

            if store.selectedRecords.isEmpty {
                emptyContentCard(
                    title: "还没有健康记录",
                    message: "点击上方健康卡片，添加第一条疫苗、驱虫、体检或就医记录。",
                    symbol: "list.bullet.clipboard"
                )
            } else {
                ZojiCard {
                    VStack(spacing: 0) {
                        ForEach(Array(store.selectedRecords.prefix(3).enumerated()), id: \.element.id) { index, record in
                            NavigationLink {
                                HealthRecordDetailView(recordID: record.id)
                            } label: {
                                recordRow(record)
                            }
                            .buttonStyle(.plain)
                            if index < min(store.selectedRecords.count, 3) - 1 {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }
            }
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
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.10), in: Circle())
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
                .foregroundStyle(AppTheme.accent)
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
                    .fill(AppTheme.accentSoft)
                    .frame(width: 132, height: 132)
                Circle()
                    .stroke(AppTheme.accent.opacity(0.12), lineWidth: 1)
                    .frame(width: 164, height: 164)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 10) {
                Text("先认识一下你的伙伴")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("建立宠物档案后，疫苗、驱虫、体检和就医记录都会整理在它的专属时间线里。")
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
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
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
}

private struct PetEditorPresentation: Identifiable {
    let id = UUID()
    let pet: Pet?
}

struct ReminderListView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: ReminderEditorPresentation?
    @State private var reminderPendingDeletion: ReminderItem?
    @State private var completingReminderIDs: Set<UUID> = []
    @State private var completionMessage: String?
    @State private var showsCarePlanTemplates = false

    private var activeReminders: [ReminderItem] {
        store.selectedReminders
    }

    var body: some View {
        @Bindable var store = store

        List {
            if store.pets.count > 1 {
                Section("宠物") {
                    reminderPetSwitcher
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            }

            Section("快捷计划") {
                Button {
                    showsCarePlanTemplates = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accentSoft, in: Circle())

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
                .disabled(store.pets.isEmpty)
            }

            if activeReminders.isEmpty {
                ContentUnavailableView(
                    "暂无提醒",
                    systemImage: "bell.badge",
                    description: Text("点击右上角添加疫苗、驱虫、复诊或日常护理提醒。")
                )
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
        .background(AppTheme.background)
        .navigationTitle("健康提醒")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = ReminderEditorPresentation(reminder: nil, petID: store.selectedPetID)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(store.pets.isEmpty)
                .accessibilityLabel("添加提醒")
            }
        }
        .sheet(item: $editor) { presentation in
            ReminderEditorView(reminder: presentation.reminder, initialPetID: presentation.petID)
                .environment(store)
        }
        .sheet(isPresented: $showsCarePlanTemplates) {
            CarePlanTemplatePickerView(initialPetID: store.selectedPetID)
                .environment(store)
        }
        .confirmationDialog(
            "删除这条提醒？",
            isPresented: Binding(
                get: { reminderPendingDeletion != nil },
                set: { if !$0 { reminderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除提醒", role: .destructive) {
                guard let reminder = reminderPendingDeletion else { return }
                Task {
                    do {
                        try await store.deleteReminder(id: reminder.id)
                    } catch {
                        store.reminderPersistenceMessage = error.localizedDescription
                    }
                    reminderPendingDeletion = nil
                }
            }
            Button("取消", role: .cancel) { reminderPendingDeletion = nil }
        }
        .alert("提醒操作失败", isPresented: Binding(
            get: { store.reminderPersistenceMessage != nil },
            set: { if !$0 { store.reminderPersistenceMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(store.reminderPersistenceMessage ?? "请稍后再试。")
        }
        .alert("系统通知未开启", isPresented: Binding(
            get: { store.notificationPermissionMessage != nil },
            set: { if !$0 { store.notificationPermissionMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(store.notificationPermissionMessage ?? "提醒仍会保存在 App 中。")
        }
        .alert("提醒已完成", isPresented: Binding(
            get: { completionMessage != nil },
            set: { if !$0 { completionMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(completionMessage ?? "已更新待办。")
        }
    }

    @ViewBuilder
    private func reminderSection(title: String, reminders: [ReminderItem]) -> some View {
        Section {
            ForEach(reminders) { reminder in
                let completionLocked = reminder.isCompletionLocked()
                HStack(spacing: 12) {
                    Button {
                        editor = ReminderEditorPresentation(reminder: reminder, petID: reminder.petID)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: reminder.kind.symbol)
                                .font(.headline)
                                .foregroundStyle(reminder.isOverdue ? AppTheme.warning : AppTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(
                                    (reminder.isOverdue ? AppTheme.warning : AppTheme.accent).opacity(0.12),
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
                                .foregroundStyle(reminder.isOverdue ? AppTheme.warning : .secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

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
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        reminderPendingDeletion = reminder
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(L10n.dynamic(title))
        }
    }

    private var reminderPetSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.pets) { pet in
                    let isSelected = store.selectedPetID == pet.id
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            store.selectedPetID = pet.id
                        }
                    } label: {
                        HStack(spacing: 8) {
                            PetAvatarView(
                                avatarData: pet.avatarData,
                                avatarPresetID: pet.avatarPresetID,
                                fallbackSymbol: pet.avatarSymbol,
                                size: 32,
                                background: isSelected ? .white.opacity(0.22) : AppTheme.accentSoft,
                                foreground: isSelected ? .white : AppTheme.accent
                            )
                            Text(pet.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(
                            isSelected ? AppTheme.accent : AppTheme.surfaceMuted,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看 \(pet.name) 的健康提醒")
                }
            }
        }
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
                let nextDueAt = try await store.completeReminder(id: reminder.id)
                if let nextDueAt {
                    completionMessage = String(localized: "本次已记录，下次提醒：\(L10n.date(nextDueAt, dateStyle: .long, timeStyle: .shortened))。", locale: L10n.locale)
                } else {
                    completionMessage = L10n.string("这条一次性提醒已完成并归档。")
                }
            } catch {
                store.reminderPersistenceMessage = error.localizedDescription
            }
        }
    }
}

private struct CarePlanTemplatePickerView: View {
    @Environment(AppStore.self) private var store
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
            .background(AppTheme.background)
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
                CarePlanPetSelectionView(pets: store.pets, selection: $petID)
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
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(template.localizedTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let selectedPet,
                       CarePlanTemplateCatalog.isRecommended(template, for: selectedPet) {
                        Text("推荐")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.accentSoft, in: Capsule())
                    }
                    Text(template.localizedSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("包含 \(template.steps.count) 项")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accent)
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
                .foregroundStyle(AppTheme.accent)
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
                .tint(AppTheme.accent)
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
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
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
                            ForEach(store.pets) { pet in
                                Text(pet.name).tag(Optional(pet.id))
                            }
                        }
                    }
                }

                Section("提醒内容") {
                    Picker("类型", selection: $kind) {
                        ForEach(RecordKind.allCases, id: \.self) { kind in
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
            .background(AppTheme.background)
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
            return "每 \(intervalValue) 天"
        }
        return option.displayName
    }
}
