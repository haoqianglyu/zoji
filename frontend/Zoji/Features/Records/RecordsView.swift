import PhotosUI
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum RecordTimelineScope: String, CaseIterable, Identifiable {
    case all
    case life
    case health

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: L10n.string("全部")
        case .life: L10n.string("生活")
        case .health: L10n.string("健康")
        }
    }

    func includes(_ record: HealthRecord) -> Bool {
        switch self {
        case .all: true
        case .life: record.kind == .life
        case .health: record.kind != .life
        }
    }
}

struct RecordsView: View {
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.appColorTheme) private var theme
    @State private var query = ""
    @State private var editor: HealthRecordEditorPresentation?
    @State private var lifeEditor: HealthRecordEditorPresentation?
    @State private var timelineScope = RecordTimelineScope.all
    @State private var recordPendingDeletion: HealthRecord?
    @State private var selectedExpenseYear = Calendar.autoupdatingCurrent.component(.year, from: Date())
    @State private var expenseReferenceDate = Date()

    private var selectedPet: SelectedPet? { store.selectedPet(using: familyStore) }
    private var selectablePets: [SelectedPet] { store.selectablePets(using: familyStore) }
    private var selectedRecords: [HealthRecord] { selectedPet?.records ?? [] }

    private var filteredRecords: [HealthRecord] {
        let scopedRecords = selectedRecords.filter(timelineScope.includes)
        guard !query.isEmpty else { return scopedRecords }
        return scopedRecords.filter { record in
            record.title.localizedStandardContains(query)
                || L10n.dynamic(record.title).localizedStandardContains(query)
                || record.kind.displayName.localizedStandardContains(query)
                || record.providerName?.localizedStandardContains(query) == true
                || record.localizedNotes?.localizedStandardContains(query) == true
        }
    }

    private var expenseYears: [Int] {
        let calendar = Calendar.autoupdatingCurrent
        return Set(selectedRecords.compactMap { record in
            guard (record.costCents ?? 0) > 0 else { return nil }
            return record.occurrenceYear(fallbackCalendar: calendar)
        }).sorted(by: >)
    }

    private var effectiveExpenseYear: Int {
        expenseYears.contains(selectedExpenseYear)
            ? selectedExpenseYear
            : (expenseYears.first ?? Calendar.autoupdatingCurrent.component(.year, from: expenseReferenceDate))
    }

    private var annualExpenseSummary: AnnualExpenseSummary? {
        AnnualExpenseSummary(records: selectedRecords, year: effectiveExpenseYear)
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
                if selectablePets.isEmpty {
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

                    Section {
                        Picker("记录范围", selection: $timelineScope) {
                            ForEach(RecordTimelineScope.allCases) { scope in
                                Text(scope.displayName).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if timelineScope != .life, let annualExpenseSummary {
                        Section("年度花费") {
                            if expenseYears.count > 1 {
                                Picker("统计年份", selection: Binding(
                                    get: { effectiveExpenseYear },
                                    set: { selectedExpenseYear = $0 }
                                )) {
                                    ForEach(expenseYears, id: \.self) { year in
                                        Text(year.formatted(.number.grouping(.never).locale(L10n.locale)))
                                            .tag(year)
                                    }
                                }
                            }
                            AnnualExpenseSummaryCard(summary: annualExpenseSummary)
                        }
                    }

                    if filteredRecords.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label(emptyStateTitle, systemImage: query.isEmpty ? emptyStateSymbol : "magnifyingglass")
                            } description: {
                                Text(emptyStateDescription)
                            } actions: {
                                if query.isEmpty,
                                   let selectedPet,
                                   selectedPet.canEdit {
                                    Button(emptyStateActionTitle) {
                                        presentNewRecord(for: selectedPet, prefersLife: timelineScope == .life)
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
                                        if let sharedPet = selectedPet?.sharedPet {
                                            FamilySharedRecordDetailView(sharedPet: sharedPet, recordID: record.id)
                                        } else {
                                            HealthRecordDetailView(recordID: record.id)
                                        }
                                    } label: {
                                        HealthRecordTimelineRow(record: record)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        if selectedPet?.canEdit == true {
                                            Button(role: .destructive) {
                                                recordPendingDeletion = record
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }

                                            Button {
                                                presentEditor(
                                                    for: record,
                                                    sharedPet: selectedPet?.sharedPet
                                                )
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
            .task {
                await refreshExpenseReferenceDateAtMidnight()
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索文字、类型或地点"
            )
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            guard let selectedPet else { return }
                            presentNewRecord(for: selectedPet, prefersLife: true)
                        } label: {
                            Label("记录生活", systemImage: "camera.fill")
                        }

                        Button {
                            guard let selectedPet else { return }
                            presentNewRecord(for: selectedPet, prefersLife: false)
                        } label: {
                            Label("添加健康记录", systemImage: "heart.text.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedPet == nil || selectedPet?.canEdit == false)
                    .accessibilityLabel("新增记录")
                }
            }
            .sheet(item: $editor) { presentation in
                HealthRecordEditorView(
                    record: presentation.record,
                    initialPetID: presentation.petID,
                    sharedPet: presentation.sharedPet
                )
                    .environment(store)
            }
            .sheet(item: $lifeEditor) { presentation in
                LifeRecordEditorView(
                    record: presentation.record,
                    initialPetID: presentation.petID,
                    sharedPet: presentation.sharedPet
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
                Button("删除记录", role: .destructive) {
                    guard let record = recordPendingDeletion else { return }
                    deleteRecord(record)
                }
                Button("取消", role: .cancel) { recordPendingDeletion = nil }
            } message: {
                Text("删除后，该记录会从 \(selectedPet?.pet.name ?? "宠物") 的时间线中移除；如果它关联了提醒，提醒也会一并删除。")
            }
            .alert("记录操作失败", isPresented: Binding(
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
        SelectedPetSwitcher(
            pets: selectablePets,
            selectedID: selectedPet?.id,
            style: .capsule,
            purpose: .records,
            onSelect: { selection in
                withAnimation(.snappy(duration: 0.25)) {
                    store.select(selection, using: familyStore)
                }
            }
        )
    }

    private var emptyStateTitle: String {
        guard query.isEmpty else { return L10n.string("没有找到记录") }
        switch timelineScope {
        case .all: return L10n.string("还没有记录")
        case .life: return L10n.string("还没有生活记录")
        case .health: return L10n.string("还没有健康记录")
        }
    }

    private var emptyStateSymbol: String {
        timelineScope == .life ? "camera.circle" : "heart.text.clipboard"
    }

    private var emptyStateDescription: String {
        guard query.isEmpty else { return L10n.string("换个关键词搜索文字、类型或地点。") }
        switch timelineScope {
        case .all:
            return L10n.string("记录日常瞬间，也保留疫苗、驱虫和就医等健康信息。")
        case .life:
            return L10n.string("从一次散步、一张照片或一句话开始，保存和宠物相处的日常。")
        case .health:
            return L10n.string("从第一次疫苗、驱虫或体检开始，建立专属健康时间线。")
        }
    }

    private var emptyStateActionTitle: String {
        timelineScope == .life ? L10n.string("记录今天") : L10n.string("添加第一条记录")
    }

    private func presentNewRecord(for pet: SelectedPet, prefersLife: Bool) {
        let presentation = HealthRecordEditorPresentation(
            record: nil,
            petID: pet.pet.id,
            sharedPet: pet.sharedPet
        )
        if prefersLife {
            lifeEditor = presentation
        } else {
            editor = presentation
        }
    }

    private func deleteRecord(_ record: HealthRecord) {
        Task {
            defer { recordPendingDeletion = nil }
            do {
                if let sharedPet = selectedPet?.sharedPet {
                    try await familyStore.deleteHealthRecord(record, in: sharedPet)
                } else {
                    try await store.deleteHealthRecord(id: record.id)
                }
            } catch {
                store.recordPersistenceMessage = error.localizedDescription
            }
        }
    }

    private func presentEditor(for record: HealthRecord, sharedPet: FamilySharedPet?) {
        if let sharedPet {
            let presentation = HealthRecordEditorPresentation(
                record: record,
                petID: record.petID,
                sharedPet: sharedPet
            )
            if record.kind == .life {
                lifeEditor = presentation
            } else {
                editor = presentation
            }
            return
        }

        Task { @MainActor in
            do {
                guard let completeRecord = try await store.healthRecordWithAttachments(id: record.id) else {
                    store.recordPersistenceMessage = L10n.string("这条健康记录已不存在。")
                    return
                }
                let presentation = HealthRecordEditorPresentation(
                    record: completeRecord,
                    petID: completeRecord.petID
                )
                if completeRecord.kind == .life {
                    lifeEditor = presentation
                } else {
                    editor = presentation
                }
            } catch {
                store.recordPersistenceMessage = String(localized: "读取健康记录附件失败：\(error.localizedDescription)", locale: L10n.locale)
            }
        }
    }

    private func refreshExpenseReferenceDateAtMidnight() async {
        while !Task.isCancelled {
            let calendar = Calendar.autoupdatingCurrent
            let now = Date()
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
                return
            }
            do {
                try await Task.sleep(for: .seconds(max(nextDay.timeIntervalSince(now), 1)))
            } catch {
                return
            }
            let previousYear = calendar.component(.year, from: expenseReferenceDate)
            expenseReferenceDate = Date()
            let currentYear = calendar.component(.year, from: expenseReferenceDate)
            if currentYear != previousYear {
                selectedExpenseYear = currentYear
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

    init?(records: [HealthRecord], year: Int, calendar: Calendar = .autoupdatingCurrent) {
        let paidRecords = records.filter {
            $0.occurrenceYear(fallbackCalendar: calendar) == year && ($0.costCents ?? 0) > 0
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: AnnualExpenseSummary
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 14 : 0) {
            Button {
                withAnimation(.snappy(duration: 0.28)) {
                    isExpanded.toggle()
                }
            } label: {
                expenseHeader
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                Divider()

                ForEach(summary.currencyGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        if summary.currencyGroups.count > 1 {
                            Text(RegionalFormat.currencyString(minorUnits: group.totalMinorUnits, code: group.code))
                                .font(.subheadline.bold())
                                .foregroundStyle(theme.accentDeep)
                        }

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

                Text("不同币种分别统计，不进行汇率换算。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if summary.currencyGroups.contains(where: { $0.code == "XXX" }) {
                    Text("部分记录的币种未知，已单独列出且未并入人民币。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var expenseHeader: some View {
        if dynamicTypeSize >= .xxLarge {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    expenseIcon
                    expenseIdentity
                    Spacer(minLength: 8)
                    expansionChevron
                }
                expenseTotals
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 12) {
                expenseIcon
                expenseIdentity
                Spacer(minLength: 10)
                expenseTotals
                expansionChevron
            }
        }
    }

    private var expenseIcon: some View {
        Image(systemName: "chart.pie.fill")
            .font(.headline)
            .foregroundStyle(theme.accent)
            .frame(width: 40, height: 40)
            .background(theme.accentSoft, in: Circle())
    }

    private var expenseIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.year.formatted(.number.grouping(.never).locale(L10n.locale)))
                .font(.headline)
            Text("\(summary.recordCount) 笔含费用记录")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var expenseTotals: some View {
        VStack(alignment: dynamicTypeSize >= .xxLarge ? .leading : .trailing, spacing: 2) {
            ForEach(summary.currencyGroups) { group in
                Text(RegionalFormat.currencyString(minorUnits: group.totalMinorUnits, code: group.code))
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.accentDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var expansionChevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }
}

struct LifeRecordEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme

    let record: HealthRecord?
    private let sharedPet: FamilySharedPet?
    @State private var petID: UUID
    @State private var occurredAt: Date
    @State private var notes: String
    @State private var location: String
    @State private var attachments: [HealthRecordAttachment]
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var gallery: HealthRecordAttachmentGalleryPresentation?
    @State private var isLoadingPhotos = false
    @State private var isSaving = false
    @State private var processingMessage: String?
    @State private var errorMessage: String?
    @FocusState private var isTextFocused: Bool

    init(record: HealthRecord?, initialPetID: UUID, sharedPet: FamilySharedPet? = nil) {
        self.record = record
        self.sharedPet = sharedPet
        _petID = State(initialValue: record?.petID ?? initialPetID)
        _occurredAt = State(initialValue: record?.occurredAt ?? Date())
        _notes = State(initialValue: record?.localizedNotes ?? "")
        _location = State(initialValue: record?.providerName ?? "")
        _attachments = State(initialValue: record?.attachments.filter { $0.kind == .image } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                petSection

                Section {
                    TextEditor(text: $notes)
                        .focused($isTextFocused)
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("今天和宠物发生了什么？")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("这一刻")
                } footer: {
                    Text("可以只写一句话，也可以只分享照片。仅你和有权限的家庭成员可见。")
                }

                Section("时间与地点") {
                    DatePicker(
                        "发生时间",
                        selection: $occurredAt,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField("地点（选填）", text: $location)
                }

                Section {
                    photoEditor
                } header: {
                    Text("照片")
                } footer: {
                    Text("最多 9 张；照片会在本机压缩后保存和同步。")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background)
            .navigationTitle(record == nil ? "记录生活" : "编辑生活记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave || isSaving || isLoadingPhotos)
                }
            }
            .onChange(of: notes) { _, value in
                if value.count > 2_000 { notes = String(value.prefix(2_000)) }
            }
            .onChange(of: location) { _, value in
                if value.count > 120 { location = String(value.prefix(120)) }
            }
            .onChange(of: selectedPhotos) { _, items in
                loadPhotos(items)
            }
            .fullScreenCover(item: $gallery) { presentation in
                HealthRecordAttachmentGallery(
                    attachments: presentation.attachments,
                    initialAttachmentID: presentation.initialAttachmentID
                )
            }
            .interactiveDismissDisabled(isSaving || isLoadingPhotos)
            .alert("无法保存生活记录", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "请稍后再试。")
            }
        }
    }

    @ViewBuilder
    private var petSection: some View {
        if let sharedPet {
            Section("记录对象") {
                LabeledContent("宠物", value: sharedPet.pet.name)
            }
        } else if record == nil, store.activePets.count > 1 {
            Section("记录对象") {
                Picker("宠物", selection: $petID) {
                    ForEach(store.activePets) { pet in
                        Text(pet.name).tag(pet.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var photoEditor: some View {
        if !attachments.isEmpty {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(attachments) { attachment in
                    photoTile(attachment)
                }
            }
            .padding(.vertical, 2)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: 46, height: 46)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加今天的照片")
                        .font(.headline)
                    Text("散步、玩耍、旅行或成长瞬间")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if attachments.count < HealthRecordAttachmentPolicy.maximumCount {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: HealthRecordAttachmentPolicy.maximumCount - attachments.count,
                matching: .images
            ) {
                Label("选择照片", systemImage: "photo.badge.plus")
            }
            .disabled(isLoadingPhotos)
        }

        if isLoadingPhotos {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在处理照片…")
                    .foregroundStyle(.secondary)
            }
        } else if let processingMessage {
            Label(processingMessage, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(theme.accent)
        }
    }

    private func photoTile(_ attachment: HealthRecordAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                gallery = HealthRecordAttachmentGalleryPresentation(
                    attachments: attachments,
                    initialAttachmentID: attachment.id
                )
            } label: {
                theme.surfaceMuted
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image = UIImage(data: attachment.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看照片")

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
                    .padding(5)
            }
            .accessibilityLabel("移除照片")
        }
    }

    private var canSave: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        processingMessage = nil

        Task {
            defer {
                isLoadingPhotos = false
                selectedPhotos = []
            }

            var accepted: [HealthRecordAttachment] = []
            var failedCount = 0
            var sourceBytes = 0
            var storedBytes = 0
            var currentBytes = attachments.reduce(0) { $0 + $1.data.count }
            let slots = max(0, HealthRecordAttachmentPolicy.maximumCount - attachments.count)

            for item in items.prefix(slots) {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw HealthRecordAttachmentValidationError.unreadableImage
                    }
                    let processed = try await Task.detached(priority: .userInitiated) {
                        try HealthRecordEditorView.processCaseImage(data)
                    }.value
                    try HealthRecordAttachmentPolicy.validateAddition(
                        kind: .image,
                        byteCount: processed.data.count,
                        currentCount: attachments.count + accepted.count,
                        currentBytes: currentBytes
                    )
                    accepted.append(HealthRecordAttachment(
                        data: processed.data,
                        originalName: "life-photo.jpg"
                    ))
                    sourceBytes += processed.sourceByteCount
                    storedBytes += processed.data.count
                    currentBytes += processed.data.count
                } catch {
                    failedCount += 1
                }
            }

            attachments.append(contentsOf: accepted)
            if !accepted.isEmpty {
                processingMessage = sourceBytes > storedBytes
                    ? String(localized: "已添加 \(accepted.count) 张，压缩 \(HealthRecordAttachmentPolicy.formattedByteCount(sourceBytes)) → \(HealthRecordAttachmentPolicy.formattedByteCount(storedBytes))", locale: L10n.locale)
                    : String(localized: "已添加 \(accepted.count) 张图片", locale: L10n.locale)
            }
            if failedCount > 0 {
                errorMessage = String(localized: "有 \(failedCount) 张照片未能添加，请换一张重试。", locale: L10n.locale)
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                guard canSave else { throw LifeRecordValidationError.contentRequired }
                try HealthRecordAttachmentPolicy.validate(attachments)
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = generatedTitle(from: trimmedNotes)

                if let sharedPet {
                    let savedRecord = HealthRecord(
                        id: record?.id ?? UUID(),
                        petID: petID,
                        kind: .life,
                        title: title,
                        occurredAt: occurredAt,
                        providerName: trimmedLocation.isEmpty ? nil : trimmedLocation,
                        costCents: nil,
                        currencyCode: nil,
                        timeZoneIdentifier: record?.timeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                        attachments: attachments
                    )
                    try await familyStore.saveHealthRecord(savedRecord, in: sharedPet)
                } else if let record {
                    try await store.updateHealthRecord(
                        id: record.id,
                        kind: .life,
                        title: title,
                        occurredAt: occurredAt,
                        providerName: trimmedLocation,
                        costCents: nil,
                        notes: trimmedNotes,
                        attachments: attachments
                    )
                } else {
                    try await store.addHealthRecord(
                        petID: petID,
                        kind: .life,
                        title: title,
                        occurredAt: occurredAt,
                        providerName: trimmedLocation,
                        costCents: nil,
                        notes: trimmedNotes,
                        attachments: attachments
                    )
                }
                if sharedPet == nil { familyStore.selectPrivatePet() }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func generatedTitle(from text: String) -> String {
        // Store the catalog key instead of a localized value so a photo-only
        // entry follows the app language when it changes later.
        guard !text.isEmpty else { return "生活记录" }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(firstLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
}

private enum LifeRecordValidationError: LocalizedError {
    case contentRequired

    var errorDescription: String? {
        L10n.string("写点内容或至少添加一张照片。")
    }
}

struct HealthRecordEditorPresentation: Identifiable {
    let id = UUID()
    let record: HealthRecord?
    let petID: UUID
    let sharedPet: FamilySharedPet?

    init(record: HealthRecord?, petID: UUID, sharedPet: FamilySharedPet? = nil) {
        self.record = record
        self.petID = petID
        self.sharedPet = sharedPet
    }
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
    @State private var recognitionTask: Task<Void, Never>?
    @State private var recognitionMessage: String?
    @State private var setsReminder = false
    @State private var reminderDueAt: Date
    @State private var reminderRepeatOption: ReminderRepeatOption = .none
    @State private var reminderCustomIntervalDays = "20"
    @State private var reminderAdvanceDays: Set<Int> = [1, 0]
    @State private var linkedReminderID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var errorTitle = L10n.string("无法保存")
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
        _notes = State(initialValue: record?.localizedNotes ?? "")
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
            .onDisappear {
                recognitionTask?.cancel()
                recognitionTask = nil
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
            .alert(errorTitle, isPresented: Binding(
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
        if sharedPet == nil, record == nil, store.activePets.count > 1 {
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
            Text("最多 9 个、总计 75 MB。文字识别仅在点击扫描按钮后于本机进行；多张图片可连续识别，保存前请核对内容。")
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
            HealthRecordPetSelectionView(pets: store.activePets, selection: $petID)
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

        if attachments.filter({ $0.kind == .image }).count > 1 {
            Button {
                recognizeAllImageAttachments()
            } label: {
                Label("识别全部图片", systemImage: "text.viewfinder")
            }
            .buttonStyle(.bordered)
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
                let linkedReminderInterval = try validatedLinkedReminderInterval()
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
                        timeZoneIdentifier: record?.timeZoneIdentifier
                            ?? TimeZone.autoupdatingCurrent.identifier,
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
                try await saveLinkedReminder(
                    recordID: savedRecordID,
                    intervalValue: linkedReminderInterval
                )
                if sharedPet == nil {
                    familyStore.selectPrivatePet()
                }
                dismiss()
            } catch {
                errorTitle = L10n.string("无法保存")
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

    private func validatedLinkedReminderInterval() throws -> Int? {
        guard setsReminder else { return nil }
        guard !reminderAdvanceDays.isEmpty else {
            throw ReminderValidationError.invalidAdvanceDays
        }
        return try reminderIntervalValue()
    }

    private func saveLinkedReminder(recordID: UUID, intervalValue: Int?) async throws {
        if let sharedPet {
            if setsReminder {
                let reminder = ReminderItem(
                    id: linkedReminderID ?? UUID(),
                    petID: petID,
                    sourceRecordID: recordID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    dueAt: reminderDueAt,
                    scheduleType: reminderRepeatOption.scheduleType,
                    intervalValue: intervalValue,
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
            if let linkedReminderID {
                try await store.updateReminder(
                    id: linkedReminderID,
                    petID: petID,
                    title: title,
                    kind: kind,
                    dueAt: reminderDueAt,
                    scheduleType: reminderRepeatOption.scheduleType,
                    intervalValue: intervalValue,
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
                    intervalValue: intervalValue,
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

        recognitionTask?.cancel()
        recognitionTask = Task {
            defer { recognizingAttachmentID = nil }
            do {
                let result = try await MedicalRecordRecognitionService.recognize(imageData: attachment.data)
                try Task.checkCancellation()
                guard attachments.contains(where: { $0.id == attachment.id }) else { return }
                applyRecognitionResult(result)
            } catch is CancellationError {
                return
            } catch {
                errorTitle = L10n.string("无法识别")
                errorMessage = String(
                    localized: "无法识别这张图片：\(error.localizedDescription)",
                    locale: L10n.locale
                )
            }
        }
    }

    private func recognizeAllImageAttachments() {
        let imageAttachments = attachments.filter { $0.kind == .image }
        guard imageAttachments.count > 1, recognizingAttachmentID == nil else { return }
        recognitionMessage = nil

        recognitionTask?.cancel()
        recognitionTask = Task {
            var recognizedCount = 0
            var failedCount = 0
            var failureReasons: [String] = []
            defer { recognizingAttachmentID = nil }

            for attachment in imageAttachments {
                do {
                    try Task.checkCancellation()
                    guard attachments.contains(where: { $0.id == attachment.id }) else { continue }
                    recognizingAttachmentID = attachment.id
                    let result = try await MedicalRecordRecognitionService.recognize(imageData: attachment.data)
                    try Task.checkCancellation()
                    guard attachments.contains(where: { $0.id == attachment.id }) else { continue }
                    applyRecognitionResult(result)
                    recognizedCount += 1
                } catch is CancellationError {
                    return
                } catch {
                    failedCount += 1
                    let reason = error.localizedDescription
                    if !failureReasons.contains(reason) {
                        failureReasons.append(reason)
                    }
                }
            }

            if recognizedCount == 0 {
                errorTitle = L10n.string("无法识别")
                if let reason = failureReasons.first {
                    errorMessage = String(
                        localized: "这些图片均未识别成功：\(reason)",
                        locale: L10n.locale
                    )
                } else {
                    errorMessage = L10n.string("这些图片均未识别成功，请选择更清晰的图片重试。")
                }
            } else if failedCount > 0 {
                recognitionMessage = String(
                    localized: "识别完成：\(recognizedCount) 张；未成功：\(failedCount) 张",
                    locale: L10n.locale
                )
            } else {
                recognitionMessage = String(
                    localized: "识别完成：\(recognizedCount) 张，已合并到详情",
                    locale: L10n.locale
                )
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
        let existingNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingNotes.isEmpty {
            notes = String(trimmedText.prefix(5_000))
            filledFields.append(L10n.string("详情"))
        } else if !existingNotes.contains(trimmedText), notes.count < 5_000 {
            let separator = "\n\n"
            let remainingCount = max(0, 5_000 - notes.count - separator.count)
            if remainingCount > 0 {
                notes += separator + String(trimmedText.prefix(remainingCount))
                filledFields.append(L10n.string("详情（已追加）"))
            }
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
            costAmount = RegionalFormat.numberInputString(cost)
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
            List(RecordKind.healthCases, id: \.self) { kind in
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
    @State private var lifeEditor: HealthRecordEditorPresentation?
    @State private var attachmentGallery: HealthRecordAttachmentGalleryPresentation?
    @State private var isConfirmingDeletion = false
    @State private var loadedRecord: HealthRecord?
    @State private var hasLoadedAttachmentData = false

    private var record: HealthRecord? {
        loadedRecord ?? store.records.first { $0.id == recordID }
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

                    Section(record.kind == .life ? "记录信息" : "记录详情") {
                        LabeledContent("宠物", value: store.pets.first(where: { $0.id == record.petID })?.name ?? "未知")
                        LabeledContent(
                            record.kind == .life ? "发生时间" : "发生日期",
                            value: L10n.date(
                                record.occurredAt,
                                dateStyle: .long,
                                timeStyle: record.kind == .life ? .shortened : .omitted
                            )
                        )
                        if let provider = record.providerName {
                            LabeledContent(record.kind == .life ? "地点" : "医院/机构", value: provider)
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

                    if let notes = record.localizedNotes {
                        Section(record.kind == .life ? "这一刻" : "详情") {
                            Text(notes)
                                .textSelection(.enabled)
                        }
                    }

                    if hasLoadedAttachmentData, !record.attachments.isEmpty {
                        Section(record.kind == .life ? "照片" : "附件") {
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
                .navigationTitle(record.kind == .life ? "生活记录" : "记录详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("编辑") {
                            let presentation = HealthRecordEditorPresentation(record: record, petID: record.petID)
                            if record.kind == .life {
                                lifeEditor = presentation
                            } else {
                                editor = presentation
                            }
                        }
                        .disabled(!hasLoadedAttachmentData)
                    }
                }
                .sheet(item: $editor) { presentation in
                    HealthRecordEditorView(record: presentation.record, initialPetID: presentation.petID)
                        .environment(store)
                }
                .sheet(item: $lifeEditor) { presentation in
                    LifeRecordEditorView(record: presentation.record, initialPetID: presentation.petID)
                        .environment(store)
                }
                .fullScreenCover(item: $attachmentGallery) { presentation in
                    HealthRecordAttachmentGallery(
                        attachments: presentation.attachments,
                        initialAttachmentID: presentation.initialAttachmentID
                    )
                }
                .confirmationDialog("删除“\(record.title)”？", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
                    Button("删除记录", role: .destructive) { deleteRecord(record) }
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("此操作会将记录从时间线中移除；如果它关联了提醒，提醒也会一并删除。")
                }
                .alert("记录操作失败", isPresented: Binding(
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
        .task(id: recordID) {
            do {
                loadedRecord = try await store.healthRecordWithAttachments(id: recordID)
                hasLoadedAttachmentData = true
            } catch {
                store.recordPersistenceMessage = String(localized: "读取健康记录附件失败：\(error.localizedDescription)", locale: L10n.locale)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: HealthRecord

    var body: some View {
        Group {
            if dynamicTypeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 13) {
                        dateColumn
                        kindIcon
                        titleColumn
                        Spacer(minLength: 0)
                    }
                    costLabel
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 13) {
                    dateColumn
                    kindIcon
                    titleColumn
                    Spacer(minLength: 4)
                    costLabel
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var dateColumn: some View {
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
    }

    private var kindIcon: some View {
        Image(systemName: record.kind.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.accent)
            .frame(width: 38, height: 38)
            .background(theme.accentSoft, in: Circle())
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizedTitle)
                .font(.headline)
                .lineLimit(dynamicTypeSize >= .xxLarge ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
            if let secondaryText {
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var costLabel: some View {
        if let cost = record.costCents {
            Text(RegionalFormat.currencyString(minorUnits: cost, code: record.resolvedCurrencyCode))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
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
