import PhotosUI
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordsView: View {
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.appColorTheme) private var theme
    @State private var query = ""
    @State private var editor: HealthRecordEditorPresentation?
    @State private var recordPendingDeletion: HealthRecord?

    private var selectedRecords: [HealthRecord] {
        familyStore.selectedSharedPet?.records.sorted { $0.occurredAt > $1.occurredAt }
            ?? store.selectedRecords
    }

    private var filteredRecords: [HealthRecord] {
        guard !query.isEmpty else { return selectedRecords }
        return selectedRecords.filter { record in
            record.title.localizedStandardContains(query)
                || record.kind.displayName.localizedStandardContains(query)
                || record.providerName?.localizedStandardContains(query) == true
        }
    }

    private var annualExpenseSummary: AnnualExpenseSummary? {
        AnnualExpenseSummary(records: selectedRecords)
    }

    private var monthSections: [HealthRecordMonthSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredRecords) { record in
            calendar.date(from: calendar.dateComponents([.year, .month], from: record.occurredAt))
                ?? calendar.startOfDay(for: record.occurredAt)
        }
        return groups
            .map { HealthRecordMonthSection(month: $0.key, records: $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            List {
                if store.pets.isEmpty && familyStore.sharedPets.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "先添加宠物",
                            systemImage: "pawprint.circle",
                            description: Text("请先在首页创建宠物档案，再为它记录疫苗、驱虫和就医信息。")
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("记录对象") {
                        petSwitcher
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }

                    if let annualExpenseSummary {
                        Section("年度花费") {
                            AnnualExpenseSummaryCard(summary: annualExpenseSummary)
                        }
                    }

                    if filteredRecords.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label(query.isEmpty ? "还没有健康记录" : "没有找到记录", systemImage: query.isEmpty ? "heart.text.clipboard" : "magnifyingglass")
                            } description: {
                                Text(query.isEmpty ? "从第一次疫苗、驱虫或体检开始，建立专属健康时间线。" : "换个关键词搜索标题、类型或医院。")
                            } actions: {
                                if query.isEmpty,
                                   let petID = familyStore.selectedSharedPet?.pet.id ?? store.selectedPetID,
                                   familyStore.selectedSharedPet?.canEdit != false {
                                    Button("添加第一条记录") {
                                        editor = HealthRecordEditorPresentation(record: nil, petID: petID)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(monthSections) { section in
                            Section {
                                ForEach(section.records) { record in
                                    NavigationLink {
                                        if let sharedPet = familyStore.selectedSharedPet {
                                            FamilySharedRecordDetailView(sharedPet: sharedPet, recordID: record.id)
                                        } else {
                                            HealthRecordDetailView(recordID: record.id)
                                        }
                                    } label: {
                                        HealthRecordTimelineRow(record: record)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        if familyStore.selectedSharedPet?.canEdit != false {
                                            Button(role: .destructive) {
                                                recordPendingDeletion = record
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }

                                            Button {
                                                editor = HealthRecordEditorPresentation(record: record, petID: record.petID)
                                            } label: {
                                                Label("编辑", systemImage: "pencil")
                                            }
                                            .tint(theme.accent)
                                        }
                                    }
                                }
                            } header: {
                                Text(
                                    section.month.formatted(
                                        .dateTime
                                            .year()
                                            .month(.wide)
                                            .locale(L10n.locale)
                                    )
                                )
                            }
                        }
                    }
                }
            }
            .refreshable {
                await store.reloadPersistedAndFamilyData(using: familyStore)
                await familyStore.synchronizePendingChanges()
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .searchable(text: $query, prompt: "搜索记录、类型或医院")
            .navigationTitle("健康记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let petID = familyStore.selectedSharedPet?.pet.id ?? store.selectedPetID else { return }
                        editor = HealthRecordEditorPresentation(record: nil, petID: petID)
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .disabled((familyStore.selectedSharedPet?.pet.id ?? store.selectedPetID) == nil || familyStore.selectedSharedPet?.canEdit == false)
                    .accessibilityLabel("新增健康记录")
                }
            }
            .sheet(item: $editor) { presentation in
                HealthRecordEditorView(
                    record: presentation.record,
                    initialPetID: presentation.petID,
                    sharedPet: familyStore.selectedSharedPet
                )
                    .environment(store)
            }
            .confirmationDialog(
                "删除“\(recordPendingDeletion?.title ?? "这条记录")”？",
                isPresented: Binding(
                    get: { recordPendingDeletion != nil },
                    set: { if !$0 { recordPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除健康记录", role: .destructive) {
                    guard let record = recordPendingDeletion else { return }
                    deleteRecord(record)
                }
                Button("取消", role: .cancel) { recordPendingDeletion = nil }
            } message: {
                Text("删除后，该记录会从 \(familyStore.selectedSharedPet?.pet.name ?? store.selectedPet?.name ?? "宠物") 的健康时间线中移除。")
            }
            .alert("健康记录操作失败", isPresented: Binding(
                get: { store.recordPersistenceMessage != nil },
                set: { if !$0 { store.recordPersistenceMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(store.recordPersistenceMessage ?? "请稍后再试。")
            }
        }
    }

    private var petSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.pets) { pet in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            store.selectedPetID = pet.id
                            familyStore.selectPrivatePet()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            PetAvatarView(
                                avatarData: pet.avatarData,
                                avatarPresetID: pet.avatarPresetID,
                                fallbackSymbol: pet.avatarSymbol,
                                size: 32,
                                background: familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id ? .white.opacity(0.22) : theme.accentSoft,
                                foreground: familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id ? .white : theme.accent
                            )
                            Text(pet.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id ? .white : .primary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(familyStore.selectedSharedPetID == nil && store.selectedPetID == pet.id ? theme.accent : theme.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看 \(pet.name) 的健康记录")
                }
                ForEach(familyStore.sharedPets) { sharedPet in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            familyStore.selectedSharedPetID = sharedPet.id
                        }
                    } label: {
                        HStack(spacing: 8) {
                            PetAvatarView(
                                avatarData: sharedPet.pet.avatarData,
                                avatarPresetID: sharedPet.pet.avatarPresetID,
                                fallbackSymbol: sharedPet.pet.avatarSymbol,
                                size: 32,
                                background: familyStore.selectedSharedPetID == sharedPet.id ? .white.opacity(0.22) : theme.accentSoft,
                                foreground: familyStore.selectedSharedPetID == sharedPet.id ? .white : theme.accent
                            )
                            Text(sharedPet.pet.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Image(systemName: "person.2.fill").font(.caption2)
                        }
                        .foregroundStyle(familyStore.selectedSharedPetID == sharedPet.id ? .white : .primary)
                        .padding(.vertical, 7).padding(.horizontal, 10)
                        .background(familyStore.selectedSharedPetID == sharedPet.id ? theme.accent : theme.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func deleteRecord(_ record: HealthRecord) {
        Task {
            defer { recordPendingDeletion = nil }
            do {
                if let sharedPet = familyStore.selectedSharedPet {
                    try await familyStore.deleteHealthRecord(record, in: sharedPet)
                } else {
                    try await store.deleteHealthRecord(id: record.id)
                }
            } catch {
                store.recordPersistenceMessage = error.localizedDescription
            }
        }
    }
}

private struct AnnualExpenseSummary: Sendable {
    struct KindAmount: Identifiable, Sendable {
        let kind: RecordKind
        let minorUnits: Int
        var id: RecordKind { kind }
    }

    struct CurrencyGroup: Identifiable, Sendable {
        let code: String
        let totalMinorUnits: Int
        let kindAmounts: [KindAmount]
        var id: String { code }
    }

    let year: Int
    let recordCount: Int
    let currencyGroups: [CurrencyGroup]

    init?(records: [HealthRecord], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let year = calendar.component(.year, from: now)
        guard let start = calendar.date(from: DateComponents(year: year)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }

        let paidRecords = records.filter {
            $0.occurredAt >= start && $0.occurredAt < end && ($0.costCents ?? 0) > 0
        }
        guard !paidRecords.isEmpty else { return nil }

        let groupedByCurrency = Dictionary(grouping: paidRecords, by: \.resolvedCurrencyCode)
        let currencyGroups = groupedByCurrency.map { code, currencyRecords in
            let total = currencyRecords.reduce(0) { $0 + ($1.costCents ?? 0) }
            let byKind = Dictionary(grouping: currencyRecords, by: \.kind)
            let kindAmounts = byKind.map { kind, kindRecords in
                KindAmount(
                    kind: kind,
                    minorUnits: kindRecords.reduce(0) { $0 + ($1.costCents ?? 0) }
                )
            }
            .sorted {
                if $0.minorUnits == $1.minorUnits {
                    return $0.kind.displayName < $1.kind.displayName
                }
                return $0.minorUnits > $1.minorUnits
            }
            return CurrencyGroup(code: code, totalMinorUnits: total, kindAmounts: kindAmounts)
        }
        .sorted { $0.code < $1.code }

        self.year = year
        self.recordCount = paidRecords.count
        self.currencyGroups = currencyGroups
    }
}

private struct AnnualExpenseSummaryCard: View {
    @Environment(\.appColorTheme) private var theme
    let summary: AnnualExpenseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "chart.pie.fill")
                    .font(.headline)
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .background(theme.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.year.formatted(.number.grouping(.never).locale(L10n.locale)))
                        .font(.headline)
                    Text("\(summary.recordCount) 笔含费用记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(summary.currencyGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(RegionalFormat.currencyString(minorUnits: group.totalMinorUnits, code: group.code))
                        .font(.title3.bold())
                        .foregroundStyle(theme.accentDeep)

                    ForEach(group.kindAmounts) { item in
                        VStack(spacing: 5) {
                            HStack {
                                Label(item.kind.displayName, systemImage: item.kind.symbol)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(RegionalFormat.currencyString(minorUnits: item.minorUnits, code: group.code))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .font(.caption)

                            ProgressView(
                                value: Double(item.minorUnits),
                                total: Double(max(group.totalMinorUnits, 1))
                            )
                            .tint(theme.accent)
                        }
                    }
                }

                if group.id != summary.currencyGroups.last?.id {
                    Divider()
                }
            }

            if summary.currencyGroups.count > 1 {
                Text("不同币种分别统计，不进行汇率换算。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

struct HealthRecordEditorPresentation: Identifiable {
    let id = UUID()
    let record: HealthRecord?
    let petID: UUID
}

struct HealthRecordEditorView: View {
    @Environment(\.appColorTheme) private var theme

    private enum SelectionSheet: String, Identifiable {
        case pet
        case recordKind
        case currency

        var id: String { rawValue }
    }

    private enum FocusedField: Hashable {
        case title
        case details
        case provider
        case cost
    }

    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss

    let record: HealthRecord?
    private let sharedPet: FamilySharedPet?
    @State private var petID: UUID
    @State private var kind: RecordKind
    @State private var title: String
    @State private var occurredAt: Date
    @State private var providerName: String
    @State private var costAmount: String
    @State private var currencyCode: String
    @State private var notes: String
    @State private var attachments: [HealthRecordAttachment]
    @State private var selectedAttachmentPhotos: [PhotosPickerItem] = []
    @State private var isImportingPDFs = false
    @State private var previewedPDF: HealthRecordAttachment?
    @State private var isLoadingAttachments = false
    @State private var attachmentProcessingMessage: String?
    @State private var recognizingAttachmentID: UUID?
    @State private var recognitionMessage: String?
    @State private var setsReminder = false
    @State private var reminderDueAt: Date
    @State private var reminderRepeatOption: ReminderRepeatOption = .none
    @State private var reminderCustomIntervalDays = "20"
    @State private var reminderAdvanceDays: Set<Int> = [1, 0]
    @State private var linkedReminderID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var selectionSheet: SelectionSheet?
    @State private var showsAdvancedReminderSettings = false
    @FocusState private var focusedField: FocusedField?

    init(record: HealthRecord?, initialPetID: UUID, sharedPet: FamilySharedPet? = nil) {
        self.record = record
        self.sharedPet = sharedPet
        let initialKind = record?.kind ?? .vaccine
        _petID = State(initialValue: record?.petID ?? initialPetID)
        _kind = State(initialValue: initialKind)
        _title = State(initialValue: record?.title ?? initialKind.defaultTitle)
        _occurredAt = State(initialValue: record?.occurredAt ?? Date())
        _providerName = State(initialValue: record?.providerName ?? "")
        _notes = State(initialValue: record?.notes ?? "")
        _attachments = State(initialValue: record?.attachments ?? [])
        _reminderDueAt = State(initialValue: Calendar.current.date(byAdding: .month, value: 1, to: Date())!)
        let initialCurrencyCode = record?.currencyCode
            ?? (record?.costCents == nil ? RegionalFormat.defaultCurrencyCode : "CNY")
        _currencyCode = State(initialValue: RegionalFormat.normalizedCurrencyCode(initialCurrencyCode))
        if let minorUnits = record?.costCents {
            _costAmount = State(
                initialValue: RegionalFormat.currencyInputString(
                    minorUnits: minorUnits,
                    code: initialCurrencyCode
                )
            )
        } else {
            _costAmount = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                recordObjectSection
                recordContentSection
                supplementalInformationSection
                nextReminderSection
                attachmentsSection
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background)
            .background {
                KeyboardDismissTapBridge {
                    focusedField = nil
                }
            }
            .navigationTitle(record == nil ? "添加健康记录" : "编辑健康记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onChange(of: kind) { oldValue, newValue in
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || title == oldValue.defaultTitle {
                    title = newValue.defaultTitle
                }
            }
            .onChange(of: title) { _, value in
                if value.count > 80 { title = String(value.prefix(80)) }
            }
            .onChange(of: notes) { _, value in
                if value.count > 5_000 { notes = String(value.prefix(5_000)) }
            }
            .onChange(of: selectedAttachmentPhotos) { _, items in
                loadImages(from: items)
            }
            .task {
                restoreLinkedReminderIfNeeded()
            }
            .fileImporter(
                isPresented: $isImportingPDFs,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true,
                onCompletion: importPDFs
            )
            .sheet(item: $previewedPDF) { attachment in
                HealthRecordPDFPreview(attachment: attachment)
            }
            .sheet(item: $selectionSheet) { sheet in
                selectionView(for: sheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsAdvancedReminderSettings) {
                HealthRecordReminderSettingsView(
                    dueAt: $reminderDueAt,
                    repeatOption: $reminderRepeatOption,
                    customIntervalDays: $reminderCustomIntervalDays,
                    advanceDays: $reminderAdvanceDays
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .interactiveDismissDisabled(isSaving)
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "请检查填写内容。")
            }
        }
    }

    @ViewBuilder
    private var recordObjectSection: some View {
        if sharedPet == nil, record == nil, store.pets.count > 1 {
            Section("记录对象") {
                Button {
                    focusedField = nil
                    selectionSheet = .pet
                } label: {
                    selectionRow(
                        title: "宠物档案",
                        value: store.pets.first(where: { $0.id == petID })?.name ?? L10n.string("未知")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recordContentSection: some View {
        Section("记录内容") {
            Button {
                focusedField = nil
                selectionSheet = .recordKind
            } label: {
                selectionRow(
                    title: "类型",
                    value: kind.displayName,
                    systemImage: kind.symbol
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("记录名称")
                TextField(kind.titlePrompt, text: $title)
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        theme.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
            }

            detailsEditor
            DatePicker("发生日期", selection: $occurredAt, in: ...Date(), displayedComponents: .date)
        }
    }

    private var supplementalInformationSection: some View {
        Section {
            TextField("医院/机构（选填）", text: $providerName)
                .focused($focusedField, equals: .provider)

            HStack {
                TextField("费用（选填）", text: $costAmount)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .cost)
                Button {
                    focusedField = nil
                    selectionSheet = .currency
                } label: {
                    HStack(spacing: 7) {
                        Text(RegionalFormat.currencyPickerLabel(for: currencyCode))
                            .foregroundStyle(theme.accent)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("补充信息")
        } footer: {
            Text("记录会先安全保存在这台设备，开启 iCloud 后自动同步。")
        }
    }

    private var nextReminderSection: some View {
        Section {
            Toggle("设置下次提醒", isOn: $setsReminder)

            if setsReminder {
                DatePicker(
                    "提醒日期",
                    selection: $reminderDueAt,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )

                Picker("常用周期", selection: $reminderRepeatOption) {
                    ForEach(quickReminderOptions) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    focusedField = nil
                    showsAdvancedReminderSettings = true
                } label: {
                    selectionRow(
                        title: "更多设置",
                        value: L10n.date(reminderDueAt, dateStyle: .omitted, timeStyle: .shortened)
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("下次提醒")
        } footer: {
            if setsReminder {
                Text("提醒会关联到本条记录；时间、完整周期和提前通知可在更多设置中调整。")
            }
        }
    }

    private var quickReminderOptions: [ReminderRepeatOption] {
        var options: [ReminderRepeatOption] = [.none, .weekly, .every30Days, .monthly, .yearly]
        if !options.contains(reminderRepeatOption) {
            options.append(reminderRepeatOption)
        }
        return options
    }

    private var attachmentsSection: some View {
        Section {
            attachmentEditor
        } header: {
            Text("附件")
        } footer: {
            Text("最多 9 个、总计 75 MB。文字识别仅在点击图片上的扫描按钮后于本机进行；保存前请核对识别内容。")
        }
    }

    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("详情")
            TextEditor(text: $notes)
                .focused($focusedField, equals: .details)
                .frame(minHeight: 112)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    theme.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("详细记录症状、诊断、用药和医生建议…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
            }
        }
    }

    private func selectionRow(
        title: LocalizedStringKey,
        value: String,
        systemImage: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.accent)
            }
            Text(value)
                .foregroundStyle(theme.accent)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func selectionView(for sheet: SelectionSheet) -> some View {
        switch sheet {
        case .pet:
            HealthRecordPetSelectionView(pets: store.pets, selection: $petID)
        case .recordKind:
            HealthRecordKindSelectionView(selection: $kind)
        case .currency:
            HealthRecordCurrencySelectionView(selection: $currencyCode)
        }
    }

    @ViewBuilder
    private var attachmentEditor: some View {
        if !attachments.isEmpty {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(attachments) { attachment in
                    attachmentTile(attachment)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "paperclip")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: 46, height: 46)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加图片或 PDF")
                        .font(.headline)
                    Text("添加后可点击图片上的扫描按钮识别文字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if attachments.count < HealthRecordAttachmentPolicy.maximumCount {
            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedAttachmentPhotos,
                    maxSelectionCount: HealthRecordAttachmentPolicy.maximumCount - attachments.count,
                    matching: .images
                ) {
                    Label("图片", systemImage: "photo")
                }
                .buttonStyle(.bordered)

                Button {
                    isImportingPDFs = true
                } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
            }
            .disabled(recognizingAttachmentID != nil || isLoadingAttachments)
        }

        if isLoadingAttachments {
            HStack(spacing: 9) {
                ProgressView()
                Text("正在处理附件…")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if let attachmentProcessingMessage {
            Label(attachmentProcessingMessage, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(theme.accent)
        }

        if recognizingAttachmentID != nil {
            HStack(spacing: 9) {
                ProgressView()
                Text("正在识别病例文字…")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if let recognitionMessage {
            Label(recognitionMessage, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(theme.accent)
        }

        if !attachments.isEmpty {
            HStack {
                Text("已添加 \(attachments.count)/\(HealthRecordAttachmentPolicy.maximumCount)")
                Spacer()
                Text("共 \(HealthRecordAttachmentPolicy.formattedByteCount(attachments.reduce(0) { $0 + $1.data.count }))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func attachmentTile(_ attachment: HealthRecordAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            theme.surfaceMuted
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                Group {
                    switch attachment.kind {
                    case .image:
                        if let image = UIImage(data: attachment.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            attachmentFallback(symbol: "photo.badge.exclamationmark", title: "图片无法预览")
                        }
                    case .pdf:
                        Button {
                            previewedPDF = attachment
                        } label: {
                            if let thumbnail = Self.pdfThumbnail(from: attachment.data) {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                attachmentFallback(symbol: "doc.richtext", title: attachment.originalName)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                attachments.removeAll { $0.id == attachment.id }
                attachmentProcessingMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.58))
            }
            .padding(7)
            .accessibilityLabel("移除附件")

            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Text(HealthRecordAttachmentPolicy.formattedByteCount(attachment.data.count))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.58), in: Capsule())
                    Spacer()

                    if attachment.kind == .image {
                        Button {
                            recognizeAttachment(attachment)
                        } label: {
                            Group {
                                if recognizingAttachmentID == attachment.id {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "text.viewfinder")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.58), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(recognizingAttachmentID != nil || isLoadingAttachments)
                        .accessibilityLabel("识别文字")
                    }
                }
            }
            .padding(7)
        }
    }

    private func attachmentFallback(symbol: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(theme.accent)
            Text(L10n.dynamic(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                let costCents = try parsedCostCents()
                let savedRecordID: UUID
                if let sharedPet {
                    let savedRecord = HealthRecord(
                        id: record?.id ?? UUID(),
                        petID: petID,
                        kind: kind,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        occurredAt: occurredAt,
                        providerName: providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil : providerName.trimmingCharacters(in: .whitespacesAndNewlines),
                        costCents: costCents,
                        currencyCode: currencyCode,
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        attachments: attachments
                    )
                    guard !savedRecord.title.isEmpty else {
                        throw HealthRecordValidationError.titleRequired
                    }
                    guard savedRecord.occurredAt <= Date() else {
                        throw HealthRecordValidationError.dateInFuture
                    }
                    try HealthRecordAttachmentPolicy.validate(savedRecord.attachments)
                    try await familyStore.saveHealthRecord(savedRecord, in: sharedPet)
                    savedRecordID = savedRecord.id
                } else if let record {
                    try await store.updateHealthRecord(
                        id: record.id,
                        kind: kind,
                        title: title,
                        occurredAt: occurredAt,
                        providerName: providerName,
                        costCents: costCents,
                        currencyCode: currencyCode,
                        notes: notes,
                        attachments: attachments
                    )
                    savedRecordID = record.id
                } else {
                    let savedRecord = try await store.addHealthRecord(
                        petID: petID,
                        kind: kind,
                        title: title,
                        occurredAt: occurredAt,
                        providerName: providerName,
                        costCents: costCents,
                        currencyCode: currencyCode,
                        notes: notes,
                        attachments: attachments
                    )
                    savedRecordID = savedRecord.id
                }
                try await saveLinkedReminder(recordID: savedRecordID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restoreLinkedReminderIfNeeded() {
        guard let record, linkedReminderID == nil else { return }
        let reminders = sharedPet?.reminders ?? store.reminders
        guard let reminder = reminders.first(where: { $0.sourceRecordID == record.id && $0.isEnabled }) else {
            return
        }
        linkedReminderID = reminder.id
        setsReminder = true
        reminderDueAt = max(reminder.dueAt, Calendar.current.startOfDay(for: Date()))
        reminderRepeatOption = ReminderRepeatOption(reminder: reminder)
        if reminderRepeatOption == .customDays, let intervalValue = reminder.intervalValue {
            reminderCustomIntervalDays = String(intervalValue)
        }
        reminderAdvanceDays = Set(reminder.advanceDays)
    }

    private func saveLinkedReminder(recordID: UUID) async throws {
        if let sharedPet {
            if setsReminder {
                guard !reminderAdvanceDays.isEmpty else {
                    throw ReminderValidationError.invalidAdvanceDays
                }
                let reminder = ReminderItem(
                    id: linkedReminderID ?? UUID(),
                    petID: petID,
                    sourceRecordID: recordID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    dueAt: reminderDueAt,
                    scheduleType: reminderRepeatOption.scheduleType,
                    intervalValue: try reminderIntervalValue(),
                    advanceDays: Array(reminderAdvanceDays).sorted(by: >),
                    isEnabled: true,
                    lastCompletedAt: sharedPet.reminders.first(where: { $0.id == linkedReminderID })?.lastCompletedAt
                )
                try await familyStore.saveReminder(reminder, in: sharedPet)
            } else if let linkedReminderID,
                      let reminder = sharedPet.reminders.first(where: { $0.id == linkedReminderID }) {
                try await familyStore.deleteReminder(reminder, in: sharedPet)
            }
            return
        }

        if setsReminder {
            guard !reminderAdvanceDays.isEmpty else {
                throw ReminderValidationError.invalidAdvanceDays
            }
            if let linkedReminderID {
                try await store.updateReminder(
                    id: linkedReminderID,
                    petID: petID,
                    title: title,
                    kind: kind,
                    dueAt: reminderDueAt,
                    scheduleType: reminderRepeatOption.scheduleType,
                    intervalValue: try reminderIntervalValue(),
                    advanceDays: Array(reminderAdvanceDays)
                )
            } else {
                try await store.addReminder(
                    petID: petID,
                    sourceRecordID: recordID,
                    title: title,
                    kind: kind,
                    dueAt: reminderDueAt,
                    scheduleType: reminderRepeatOption.scheduleType,
                    intervalValue: try reminderIntervalValue(),
                    advanceDays: Array(reminderAdvanceDays)
                )
            }
        } else if let linkedReminderID {
            try await store.deleteReminder(id: linkedReminderID)
        }
    }

    private func reminderIntervalValue() throws -> Int? {
        guard reminderRepeatOption == .customDays else {
            return reminderRepeatOption.intervalValue
        }
        guard let days = Int(reminderCustomIntervalDays), (1 ... 3650).contains(days) else {
            throw ReminderValidationError.invalidInterval
        }
        return days
    }

    private func parsedCostCents() throws -> Int? {
        let trimmed = costAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let minorUnits = RegionalFormat.minorUnits(from: trimmed, code: currencyCode) else {
            throw HealthRecordValidationError.costOutOfRange
        }
        return minorUnits
    }

    struct ProcessedCaseImage: Sendable {
        let data: Data
        let sourceByteCount: Int
    }

    private struct PDFLoadResult: Sendable {
        let attachment: HealthRecordAttachment?
        let failureReason: String?
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        attachmentProcessingMessage = nil
        recognitionMessage = nil
        isLoadingAttachments = true

        Task {
            defer {
                isLoadingAttachments = false
                selectedAttachmentPhotos = []
            }

            var newAttachments: [HealthRecordAttachment] = []
            var failedCount = 0
            var failureReasons: [String] = []
            var sourceByteCount = 0
            var storedByteCount = 0
            var currentTotalBytes = attachments.reduce(0) { $0 + $1.data.count }
            let availableSlots = max(0, HealthRecordAttachmentPolicy.maximumCount - attachments.count)

            for item in items.prefix(availableSlots) {
                do {
                    guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                        throw HealthRecordAttachmentValidationError.unreadableImage
                    }
                    let processed = try await Task.detached(priority: .userInitiated) {
                        try Self.processCaseImage(sourceData)
                    }.value
                    try HealthRecordAttachmentPolicy.validateAddition(
                        kind: .image,
                        byteCount: processed.data.count,
                        currentCount: attachments.count + newAttachments.count,
                        currentBytes: currentTotalBytes
                    )

                    newAttachments.append(HealthRecordAttachment(data: processed.data))
                    sourceByteCount += processed.sourceByteCount
                    storedByteCount += processed.data.count
                    currentTotalBytes += processed.data.count
                } catch {
                    failedCount += 1
                    let reason = error.localizedDescription
                    if !failureReasons.contains(reason) {
                        failureReasons.append(reason)
                    }
                }
            }

            attachments.append(contentsOf: newAttachments)
            if !newAttachments.isEmpty {
                if sourceByteCount > storedByteCount {
                    attachmentProcessingMessage = String(localized: "已添加 \(newAttachments.count) 张，压缩 \(HealthRecordAttachmentPolicy.formattedByteCount(sourceByteCount)) → \(HealthRecordAttachmentPolicy.formattedByteCount(storedByteCount))", locale: L10n.locale)
                } else {
                    attachmentProcessingMessage = String(localized: "已添加 \(newAttachments.count) 张图片", locale: L10n.locale)
                }
            }
            if failedCount > 0 {
                let reasons = failureReasons.prefix(2).joined(separator: "；")
                errorMessage = String(localized: "有 \(failedCount) 张图片未添加：\(reasons)", locale: L10n.locale)
            }
        }
    }

    private func recognizeAttachment(_ attachment: HealthRecordAttachment) {
        guard attachment.kind == .image, recognizingAttachmentID == nil else { return }
        recognizingAttachmentID = attachment.id
        recognitionMessage = nil

        Task {
            defer { recognizingAttachmentID = nil }
            do {
                let result = try await MedicalRecordRecognitionService.recognize(imageData: attachment.data)
                guard attachments.contains(where: { $0.id == attachment.id }) else { return }
                applyRecognitionResult(result)
            } catch {
                errorMessage = L10n.string("无法识别这张图片，请选择更清晰的图片重试。")
            }
        }
    }

    private func importPDFs(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            attachmentProcessingMessage = nil
            let availableSlots = max(0, HealthRecordAttachmentPolicy.maximumCount - attachments.count)
            guard availableSlots > 0 else {
                errorMessage = HealthRecordAttachmentValidationError.tooManyAttachments.localizedDescription
                return
            }

            isLoadingAttachments = true
            Task {
                defer { isLoadingAttachments = false }
                let selectedURLs = Array(urls.prefix(availableSlots))
                let loadedResults = await Task.detached(priority: .userInitiated) {
                    selectedURLs.map(Self.loadPDFAttachment(from:))
                }.value
                var accepted: [HealthRecordAttachment] = []
                var failureReasons = loadedResults.compactMap(\.failureReason)
                var currentTotalBytes = attachments.reduce(0) { $0 + $1.data.count }

                for loaded in loadedResults.compactMap(\.attachment) {
                    do {
                        try HealthRecordAttachmentPolicy.validateAddition(
                            kind: .pdf,
                            byteCount: loaded.data.count,
                            currentCount: attachments.count + accepted.count,
                            currentBytes: currentTotalBytes
                        )
                        accepted.append(loaded)
                        currentTotalBytes += loaded.data.count
                    } catch {
                        failureReasons.append(error.localizedDescription)
                    }
                }

                let omittedCount = max(0, urls.count - selectedURLs.count)
                if omittedCount > 0 {
                    failureReasons.append("另有 \(omittedCount) 个文件超出 9 个附件上限。")
                }

                attachments.append(contentsOf: accepted)
                if !accepted.isEmpty {
                    let addedBytes = accepted.reduce(0) { $0 + $1.data.count }
                    attachmentProcessingMessage = String(localized: "已添加 \(accepted.count) 个 PDF，共 \(HealthRecordAttachmentPolicy.formattedByteCount(addedBytes))", locale: L10n.locale)
                }

                if !failureReasons.isEmpty {
                    let uniqueReasons = failureReasons.reduce(into: [String]()) { result, reason in
                        if !result.contains(reason) { result.append(reason) }
                    }
                    errorMessage = String(localized: "有 \(failureReasons.count) 个 PDF 未添加：\(uniqueReasons.prefix(2).joined(separator: "；"))", locale: L10n.locale)
                }
            }
        } catch {
            errorMessage = L10n.string("无法导入 PDF，请重新选择。")
        }
    }

    nonisolated private static func loadPDFAttachment(from url: URL) -> PDFLoadResult {
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess { url.stopAccessingSecurityScopedResource() }
        }

        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = resourceValues.fileSize,
           fileSize > HealthRecordAttachmentPolicy.maximumPDFBytes {
            return PDFLoadResult(
                attachment: nil,
                failureReason: HealthRecordAttachmentValidationError.pdfTooLarge.localizedDescription
            )
        }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return PDFLoadResult(
                attachment: nil,
                failureReason: HealthRecordAttachmentValidationError.unreadablePDF.localizedDescription
            )
        }
        guard data.count <= HealthRecordAttachmentPolicy.maximumPDFBytes else {
            return PDFLoadResult(
                attachment: nil,
                failureReason: HealthRecordAttachmentValidationError.pdfTooLarge.localizedDescription
            )
        }
        guard let document = PDFDocument(data: data),
              document.pageCount > 0,
              !document.isLocked
        else {
            return PDFLoadResult(
                attachment: nil,
                failureReason: HealthRecordAttachmentValidationError.unreadablePDF.localizedDescription
            )
        }

        return PDFLoadResult(
            attachment: HealthRecordAttachment(
                kind: .pdf,
                data: data,
                originalName: String(url.lastPathComponent.prefix(120))
            ),
            failureReason: nil
        )
    }

    nonisolated static func pdfThumbnail(from data: Data) -> UIImage? {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 360, height: 360), for: .mediaBox)
    }

    private func applyRecognitionResult(_ result: MedicalRecordRecognitionResult) {
        let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            recognitionMessage = L10n.string("没有识别到清晰文字，请尝试更清晰的图片")
            return
        }

        var filledFields: [String] = []
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = String(trimmedText.prefix(5_000))
            filledFields.append(L10n.string("详情"))
        }

        if (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == kind.defaultTitle),
           let diagnosis = result.suggestedTitle {
            title = String(diagnosis.prefix(40))
            filledFields.append(L10n.string("记录名称"))
        }

        if providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let provider = result.suggestedProvider {
            providerName = provider
            filledFields.append(L10n.string("医院/机构"))
        }

        if costAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let cost = result.suggestedCost {
            costAmount = cost
            filledFields.append(L10n.string("费用"))
        }

        if filledFields.isEmpty {
            recognitionMessage = L10n.string("文字识别完成；已有内容未被覆盖")
        } else {
            let fieldSummary = filledFields.joined(separator: L10n.usesEnglish ? ", " : "、")
            recognitionMessage = String(localized: "已辅助填写：\(fieldSummary)", locale: L10n.locale)
        }
    }

    nonisolated static func processCaseImage(_ data: Data) throws -> ProcessedCaseImage {
        guard data.count <= HealthRecordAttachmentPolicy.maximumImageSourceBytes else {
            throw HealthRecordAttachmentValidationError.imageSourceTooLarge
        }
        guard let image = UIImage(data: data) else {
            throw HealthRecordAttachmentValidationError.unreadableImage
        }
        let currentMaximum = max(image.size.width, image.size.height)
        let pixelCount = image.size.width * image.size.height
        guard currentMaximum > 0, pixelCount <= 80_000_000 else {
            throw HealthRecordAttachmentValidationError.imageSourceTooLarge
        }

        let startingDimension = min(
            currentMaximum,
            CGFloat(HealthRecordAttachmentPolicy.maximumImageDimension)
        )
        let dimensionCandidates = [startingDimension, startingDimension * 0.82, startingDimension * 0.67]
        let compressionQualities: [CGFloat] = [0.86, 0.76, 0.66, 0.54]
        var smallestData: Data?

        for maximumDimension in dimensionCandidates {
            let ratio = maximumDimension / currentMaximum
            let targetSize = CGSize(
                width: max(1, image.size.width * ratio),
                height: max(1, image.size.height * ratio)
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: targetSize))
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            for quality in compressionQualities {
                guard let candidate = resized.jpegData(compressionQuality: quality) else { continue }
                if smallestData == nil || candidate.count < smallestData!.count {
                    smallestData = candidate
                }
                if candidate.count <= HealthRecordAttachmentPolicy.preferredStoredImageBytes {
                    return ProcessedCaseImage(data: candidate, sourceByteCount: data.count)
                }
            }
        }

        guard let smallestData,
              smallestData.count <= HealthRecordAttachmentPolicy.maximumStoredImageBytes else {
            throw HealthRecordAttachmentValidationError.imageTooLarge
        }
        return ProcessedCaseImage(data: smallestData, sourceByteCount: data.count)
    }

}

private struct HealthRecordPetSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    let pets: [Pet]
    @Binding var selection: UUID

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
            .navigationTitle("宠物档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct HealthRecordKindSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    @Binding var selection: RecordKind

    var body: some View {
        NavigationStack {
            List(RecordKind.allCases, id: \.self) { kind in
                Button {
                    selection = kind
                    dismiss()
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: kind.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 34, height: 34)
                            .background(theme.accentSoft, in: Circle())
                        Text(kind.displayName)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if selection == kind {
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
            .navigationTitle("类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct HealthRecordCurrencySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    @Binding var selection: String

    var body: some View {
        NavigationStack {
            List(RegionalFormat.supportedCurrencyCodes, id: \.self) { code in
                Button {
                    selection = code
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(code)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(L10n.locale.localizedString(forCurrencyCode: code) ?? code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(RegionalFormat.currencySymbol(for: code))
                            .foregroundStyle(.secondary)
                        if selection == code {
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
            .navigationTitle("币种")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct HealthRecordReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    @Binding var dueAt: Date
    @Binding var repeatOption: ReminderRepeatOption
    @Binding var customIntervalDays: String
    @Binding var advanceDays: Set<Int>

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒时间") {
                    DatePicker(
                        "时间",
                        selection: $dueAt,
                        displayedComponents: .hourAndMinute
                    )
                }

                Section("重复周期") {
                    Picker("重复", selection: $repeatOption) {
                        ForEach(ReminderRepeatOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    if repeatOption == .customDays {
                        HStack {
                            Text("间隔天数")
                            Spacer()
                            TextField("20", text: $customIntervalDays)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 56, maxWidth: 88)
                            Text("天")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    ForEach([7, 3, 1, 0], id: \.self) { day in
                        Toggle(day == 0 ? "当天" : "提前 \(day) 天", isOn: Binding(
                            get: { advanceDays.contains(day) },
                            set: { isOn in
                                if isOn {
                                    advanceDays.insert(day)
                                } else if advanceDays.count > 1 {
                                    advanceDays.remove(day)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("提前通知")
                } footer: {
                    Text("至少保留一个通知时间。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("提醒设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isCustomIntervalValid)
                }
            }
        }
    }

    private var isCustomIntervalValid: Bool {
        guard repeatOption == .customDays else { return true }
        guard let days = Int(customIntervalDays) else { return false }
        return (1 ... 3650).contains(days)
    }
}

struct HealthRecordDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    let recordID: UUID
    @State private var editor: HealthRecordEditorPresentation?
    @State private var attachmentGallery: HealthRecordAttachmentGalleryPresentation?
    @State private var isConfirmingDeletion = false

    private var record: HealthRecord? {
        store.records.first { $0.id == recordID }
    }

    var body: some View {
        Group {
            if let record {
                List {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: record.kind.symbol)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 74, height: 74)
                                .background(theme.accentSoft, in: Circle())
                            Text(L10n.dynamic(record.title))
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text(record.kind.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }

                    Section("记录详情") {
                        LabeledContent("宠物", value: store.pets.first(where: { $0.id == record.petID })?.name ?? "未知")
                        LabeledContent("发生日期", value: L10n.date(record.occurredAt, dateStyle: .long, timeStyle: .omitted))
                        if let provider = record.providerName {
                            LabeledContent("医院/机构", value: provider)
                        }
                        if let cost = record.costCents {
                            LabeledContent(
                                "费用",
                                value: RegionalFormat.currencyString(
                                    minorUnits: cost,
                                    code: record.resolvedCurrencyCode
                                )
                            )
                        }
                    }

                    if let notes = record.notes {
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
                                    detailAttachmentTile(attachment)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section {
                        Button("删除这条记录", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(theme.background)
                .navigationTitle("记录详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("编辑") {
                            editor = HealthRecordEditorPresentation(record: record, petID: record.petID)
                        }
                    }
                }
                .sheet(item: $editor) { presentation in
                    HealthRecordEditorView(record: presentation.record, initialPetID: presentation.petID)
                        .environment(store)
                }
                .fullScreenCover(item: $attachmentGallery) { presentation in
                    HealthRecordAttachmentGallery(
                        attachments: presentation.attachments,
                        initialAttachmentID: presentation.initialAttachmentID
                    )
                }
                .confirmationDialog("删除“\(record.title)”？", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
                    Button("删除健康记录", role: .destructive) { deleteRecord(record) }
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("此操作会将记录从健康时间线中移除。")
                }
                .alert("健康记录操作失败", isPresented: Binding(
                    get: { store.recordPersistenceMessage != nil },
                    set: { if !$0 { store.recordPersistenceMessage = nil } }
                )) {
                    Button("知道了", role: .cancel) { }
                } message: {
                    Text(store.recordPersistenceMessage ?? "请稍后再试。")
                }
            } else {
                ContentUnavailableView("记录不存在", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func deleteRecord(_ record: HealthRecord) {
        Task {
            do {
                try await store.deleteHealthRecord(id: record.id)
                dismiss()
            } catch {
                store.recordPersistenceMessage = error.localizedDescription
            }
        }
    }

    private func detailAttachmentTile(_ attachment: HealthRecordAttachment) -> some View {
        Button {
            guard let record else { return }
            attachmentGallery = HealthRecordAttachmentGalleryPresentation(
                attachments: record.attachments,
                initialAttachmentID: attachment.id
            )
        } label: {
            theme.surfaceMuted
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
                                .foregroundStyle(theme.accent)
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
                .overlay(alignment: .bottomLeading) {
                    Text(HealthRecordAttachmentPolicy.formattedByteCount(attachment.data.count))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            attachment.kind == .pdf
                ? "查看 PDF \(attachment.originalName)"
                : "放大查看 \(attachment.originalName)"
        )
    }
}

private struct HealthRecordTimelineRow: View {
    @Environment(\.appColorTheme) private var theme
    let record: HealthRecord

    var body: some View {
        HStack(spacing: 13) {
            VStack(spacing: 3) {
                Text(dayText)
                    .font(.title3.bold().monospacedDigit())
                    .lineLimit(1)
                Text(weekdayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 46, alignment: .center)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.date(record.occurredAt, dateStyle: .long, timeStyle: .omitted))

            Image(systemName: record.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedTitle)
                    .font(.headline)
                    .lineLimit(1)
                if let secondaryText {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let cost = record.costCents {
                Text(RegionalFormat.currencyString(minorUnits: cost, code: record.resolvedCurrencyCode))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private var dayText: String {
        String(Calendar.current.component(.day, from: record.occurredAt))
    }

    private var weekdayText: String {
        record.occurredAt.formatted(
            .dateTime
                .weekday(.abbreviated)
                .locale(L10n.locale)
        )
    }

    private var localizedTitle: String {
        L10n.dynamic(record.title)
    }

    private var secondaryText: String? {
        if let providerName = record.providerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !providerName.isEmpty {
            return providerName
        }

        let normalizedTitle = localizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitles = [record.kind.defaultTitle, record.kind.displayName]
        return defaultTitles.contains(normalizedTitle) ? nil : record.kind.displayName
    }
}

private struct HealthRecordMonthSection: Identifiable {
    let month: Date
    let records: [HealthRecord]
    var id: Date { month }
}

struct HealthRecordAttachmentGalleryPresentation: Identifiable {
    let id = UUID()
    let attachments: [HealthRecordAttachment]
    let initialAttachmentID: UUID
}

struct HealthRecordAttachmentGallery: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    let attachments: [HealthRecordAttachment]
    @State private var selectedAttachmentID: UUID

    init(attachments: [HealthRecordAttachment], initialAttachmentID: UUID) {
        self.attachments = attachments
        _selectedAttachmentID = State(initialValue: initialAttachmentID)
    }

    private var selectedIndex: Int {
        attachments.firstIndex { $0.id == selectedAttachmentID } ?? 0
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedAttachmentID) {
                ForEach(attachments) { attachment in
                    attachmentPage(attachment)
                        .tag(attachment.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(attachments.isEmpty ? "附件" : "\(selectedIndex + 1) / \(attachments.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !attachments.isEmpty {
                        Text(attachments[selectedIndex].kind == .pdf ? "PDF" : "图片")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("关闭附件预览")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !attachments.isEmpty {
                    VStack(spacing: 4) {
                        Text(attachments[selectedIndex].originalName)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(HealthRecordAttachmentPolicy.formattedByteCount(attachments[selectedIndex].data.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.9))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func attachmentPage(_ attachment: HealthRecordAttachment) -> some View {
        switch attachment.kind {
        case .image:
            if let image = UIImage(data: attachment.data) {
                ZoomableHealthRecordImage(image: image)
                    .id(attachment.id)
            } else {
                ContentUnavailableView("图片无法预览", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
            }
        case .pdf:
            PDFKitDocumentView(data: attachment.data)
                .id(attachment.id)
        }
    }
}

private struct HealthRecordPDFPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    let attachment: HealthRecordAttachment

    var body: some View {
        NavigationStack {
            PDFKitDocumentView(data: attachment.data)
                .background(theme.background)
                .navigationTitle(attachment.originalName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

private struct HealthRecordImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: HealthRecordAttachment

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: attachment.data) {
                    ZoomableHealthRecordImage(image: image)
                } else {
                    ContentUnavailableView("图片无法预览", systemImage: "photo.badge.exclamationmark")
                }
            }
            .background(Color.black)
            .navigationTitle(attachment.originalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct ZoomableHealthRecordImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.bouncesZoom = true
        // At the minimum scale, let the surrounding paged gallery own the
        // horizontal swipe. Once zoomed in, panning moves the current image.
        scrollView.panGestureRecognizer.isEnabled = false

        let imageView = context.coordinator.imageView
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView.image = image
        if scrollView.zoomScale == scrollView.minimumZoomScale {
            context.coordinator.imageView.frame = scrollView.bounds
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            if scrollView.panGestureRecognizer.isEnabled != isZoomed {
                scrollView.panGestureRecognizer.isEnabled = isZoomed
            }
        }
    }
}

private struct PDFKitDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFKit.PDFView {
        let view = PDFKit.PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFKit.PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

/// Installs a non-blocking tap recognizer while the editor is visible. Taps on
/// an active text input are ignored; taps elsewhere dismiss the current input
/// without preventing buttons, pickers, or other controls from receiving them.
private struct KeyboardDismissTapBridge: UIViewRepresentable {
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ view: WindowTrackingView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.attach(to: view.window)
    }

    static func dismantleUIView(_ view: WindowTrackingView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class WindowTrackingView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: () -> Void
        private weak var installedWindow: UIWindow?
        private lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func attach(to window: UIWindow?) {
            guard installedWindow !== window else { return }
            detach()
            window?.addGestureRecognizer(tapRecognizer)
            installedWindow = window
        }

        func detach() {
            installedWindow?.removeGestureRecognizer(tapRecognizer)
            installedWindow = nil
        }

        @objc private func handleTap() {
            onDismiss()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

#Preview {
    RecordsView()
        .environment(AppStore.preview)
}
