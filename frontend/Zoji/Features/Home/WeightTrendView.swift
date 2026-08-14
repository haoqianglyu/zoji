import Charts
import SwiftUI

struct WeightTrendPreviewCard: View {
    let pet: Pet
    @AppStorage(AppColorTheme.storageKey) private var colorTheme = AppColorTheme.warm
    @AppStorage(AppUnitSystem.storageKey) private var unitSystem = AppUnitSystem.system

    private var entries: [WeightEntry] { pet.sortedWeightEntries }

    var body: some View {
        ZojiCard {
            HStack(spacing: 14) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(colorTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(colorTheme.accentSoft, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 4) {
                    Text("体重趋势")
                        .font(.headline)
                    if let weight = pet.weightKilograms {
                        HStack(spacing: 8) {
                            Text(RegionalFormat.massString(fromKilograms: weight))
                                .font(.subheadline.weight(.semibold))
                            if let deltaText {
                                Text(deltaText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(deltaColor)
                            }
                        }
                    } else {
                        Text("记录体重后查看变化曲线")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                if entries.count >= 2 {
                    Chart(entries.suffix(8)) { entry in
                        LineMark(
                            x: .value(L10n.string("日期"), entry.measuredAt),
                            y: .value(L10n.string("体重"), RegionalFormat.displayedMass(fromKilograms: entry.kilograms))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(colorTheme.accent)

                        AreaMark(
                            x: .value(L10n.string("日期"), entry.measuredAt),
                            y: .value(L10n.string("体重"), RegionalFormat.displayedMass(fromKilograms: entry.kilograms))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [colorTheme.accent.opacity(0.24), colorTheme.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(width: 104, height: 54)
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .id(unitSystem)
    }

    private var deltaKilograms: Double? {
        guard entries.count >= 2,
              let first = entries.dropLast().last,
              let latest = entries.last else { return nil }
        return latest.kilograms - first.kilograms
    }

    private var deltaText: String? {
        guard let deltaKilograms else { return nil }
        let displayed = RegionalFormat.displayedMass(fromKilograms: abs(deltaKilograms))
            .formatted(.number.precision(.fractionLength(0 ... 2)).locale(L10n.locale))
        let sign = deltaKilograms > 0.000_1 ? "+" : deltaKilograms < -0.000_1 ? "−" : ""
        return "\(sign)\(displayed) \(RegionalFormat.massUnitSymbol)"
    }

    private var deltaColor: Color {
        guard let deltaKilograms else { return .secondary }
        return abs(deltaKilograms) < 0.000_1 ? .secondary : colorTheme.accent
    }
}

struct WeightTrendView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(AppColorTheme.storageKey) private var colorTheme = AppColorTheme.warm
    @AppStorage(AppUnitSystem.storageKey) private var unitSystem = AppUnitSystem.system

    let petID: UUID
    var readOnlyPet: Pet?
    var canEdit = true

    @State private var selectedRange = WeightChartRange.all
    @State private var editor: WeightEntryEditorPresentation?
    @State private var entryPendingDeletion: WeightEntry?
    @State private var errorMessage: String?

    private var pet: Pet? {
        readOnlyPet ?? store.pets.first { $0.id == petID }
    }

    private var entries: [WeightEntry] { pet?.sortedWeightEntries ?? [] }

    private var filteredEntries: [WeightEntry] {
        guard let cutoff = selectedRange.cutoffDate else { return entries }
        return entries.filter { $0.measuredAt >= cutoff }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                summaryCard
                chartCard
                historySection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(colorTheme.background)
        .navigationTitle("体重趋势")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = WeightEntryEditorPresentation(entry: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加体重记录")
                }
            }
        }
        .sheet(item: $editor) { presentation in
            WeightEntryEditorView(petID: petID, entry: presentation.entry)
                .environment(store)
        }
        .confirmationDialog(
            "删除这条体重记录？",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除记录", role: .destructive) { deletePendingEntry() }
            Button("取消", role: .cancel) { entryPendingDeletion = nil }
        }
        .alert("体重记录操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "请稍后再试。")
        }
        .id(unitSystem)
    }

    private var summaryCard: some View {
        ZojiCard {
            HStack(spacing: 16) {
                PetAvatarView(
                    avatarData: pet?.avatarData,
                    avatarPresetID: pet?.avatarPresetID,
                    fallbackSymbol: pet?.avatarSymbol ?? "pawprint.fill",
                    size: 58,
                    background: colorTheme.accentSoft,
                    foreground: colorTheme.accent
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(pet?.name ?? L10n.string("宠物"))
                        .font(.headline)
                    Text("当前体重")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currentWeightText)
                        .font(.title2.bold())
                        .foregroundStyle(colorTheme.accent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text("最近变化")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(overallChangeText)
                        .font(.headline)
                    Text(String(localized: "共 \(entries.count) 次记录", locale: L10n.locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chartCard: some View {
        ZojiCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("变化曲线")
                            .font(.headline)
                        Text(RegionalFormat.massUnitSymbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("时间范围", selection: $selectedRange) {
                        ForEach(WeightChartRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 230)
                }

                if filteredEntries.isEmpty {
                    emptyChartState
                } else {
                    Chart(filteredEntries) { entry in
                        AreaMark(
                            x: .value(L10n.string("日期"), entry.measuredAt),
                            yStart: .value(L10n.string("下限"), chartDomain.lowerBound),
                            yEnd: .value(L10n.string("体重"), displayedWeight(entry))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [colorTheme.accent.opacity(0.30), colorTheme.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value(L10n.string("日期"), entry.measuredAt),
                            y: .value(L10n.string("体重"), displayedWeight(entry))
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(colorTheme.accent)

                        PointMark(
                            x: .value(L10n.string("日期"), entry.measuredAt),
                            y: .value(L10n.string("体重"), displayedWeight(entry))
                        )
                        .symbolSize(filteredEntries.count == 1 ? 72 : 34)
                        .foregroundStyle(colorTheme.accent)
                    }
                    .chartYScale(domain: chartDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(.clear)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(.secondary.opacity(0.14))
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 230)
                }
            }
        }
    }

    private var emptyChartState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 38))
                .foregroundStyle(colorTheme.accent.opacity(0.75))
            Text("还没有体重记录")
                .font(.headline)
            Text("定期记录后，这里会显示体重变化曲线。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if canEdit {
                Button("记录第一次称重") {
                    editor = WeightEntryEditorPresentation(entry: nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210)
    }

    private var historySection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("称重记录")
                    .font(.title3.bold())
                Spacer()
                if canEdit, !entries.isEmpty {
                    Button("添加") {
                        editor = WeightEntryEditorPresentation(entry: nil)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 2)

            if entries.isEmpty {
                if let weight = pet?.weightKilograms {
                    ZojiCard {
                        HStack(spacing: 12) {
                            Image(systemName: "scalemass.fill")
                                .foregroundStyle(colorTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(colorTheme.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("档案中的当前体重")
                                    .font(.subheadline.weight(.semibold))
                                Text("添加一次称重后开始建立趋势")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(RegionalFormat.massString(fromKilograms: weight))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            } else {
                ZojiCard {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.reversed().enumerated()), id: \.element.id) { index, entry in
                            weightEntryRow(entry)
                            if index < entries.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
            }
        }
    }

    private func weightEntryRow(_ entry: WeightEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .foregroundStyle(colorTheme.accent)
                .frame(width: 40, height: 40)
                .background(colorTheme.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(RegionalFormat.massString(fromKilograms: entry.kilograms))
                    .font(.headline)
                Text(L10n.date(entry.measuredAt, dateStyle: .long, timeStyle: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if canEdit {
                Menu {
                    Button {
                        editor = WeightEntryEditorPresentation(entry: entry)
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        entryPendingDeletion = entry
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(colorTheme.accent)
                }
                .accessibilityLabel("管理这条体重记录")
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canEdit else { return }
            editor = WeightEntryEditorPresentation(entry: entry)
        }
    }

    private var currentWeightText: String {
        guard let weight = pet?.weightKilograms else { return L10n.string("待补充") }
        return RegionalFormat.massString(fromKilograms: weight)
    }

    private var overallChangeText: String {
        guard entries.count >= 2,
              let first = entries.first,
              let last = entries.last else { return "—" }
        let delta = last.kilograms - first.kilograms
        let displayed = RegionalFormat.displayedMass(fromKilograms: abs(delta))
            .formatted(.number.precision(.fractionLength(0 ... 2)).locale(L10n.locale))
        let sign = delta > 0.000_1 ? "+" : delta < -0.000_1 ? "−" : ""
        return "\(sign)\(displayed) \(RegionalFormat.massUnitSymbol)"
    }

    private var chartDomain: ClosedRange<Double> {
        let values = filteredEntries.map(displayedWeight)
        guard let minimum = values.min(), let maximum = values.max() else { return 0 ... 1 }
        let spread = max(maximum - minimum, max(maximum * 0.08, 0.5))
        return max(0, minimum - spread * 0.55) ... (maximum + spread * 0.55)
    }

    private func displayedWeight(_ entry: WeightEntry) -> Double {
        RegionalFormat.displayedMass(fromKilograms: entry.kilograms)
    }

    private func deletePendingEntry() {
        guard let entry = entryPendingDeletion else { return }
        Task {
            do {
                try await store.deleteWeightEntry(petID: petID, entryID: entry.id)
                entryPendingDeletion = nil
            } catch {
                entryPendingDeletion = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

private enum WeightChartRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case oneYear
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .oneMonth: L10n.string("1月")
        case .threeMonths: L10n.string("3月")
        case .oneYear: L10n.string("1年")
        case .all: L10n.string("全部")
        }
    }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: Date())
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: Date())
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
    }
}

private struct WeightEntryEditorPresentation: Identifiable {
    let id = UUID()
    let entry: WeightEntry?
}

private struct WeightEntryEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppColorTheme.storageKey) private var colorTheme = AppColorTheme.warm

    let petID: UUID
    let entry: WeightEntry?

    @State private var weight: String
    @State private var measuredAt: Date
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var weightIsFocused: Bool

    init(petID: UUID, entry: WeightEntry?) {
        self.petID = petID
        self.entry = entry
        _weight = State(initialValue: entry.map {
            RegionalFormat.massInputString(fromKilograms: $0.kilograms)
        } ?? "")
        _measuredAt = State(initialValue: entry?.measuredAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("称重信息") {
                    LabeledContent("体重") {
                        HStack(spacing: 6) {
                            TextField("0", text: $weight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($weightIsFocused)
                            Text(RegionalFormat.massUnitSymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("称重日期", selection: $measuredAt, in: ...Date(), displayedComponents: .date)
                }

                Section {
                    Label("定期在相似时间和条件下称重，更容易看出真实变化。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(colorTheme.background)
            .navigationTitle(entry == nil ? "记录体重" : "编辑体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving || weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "请稍后再试。")
            }
            .onAppear { weightIsFocused = entry == nil }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let displayedValue = RegionalFormat.parseNumber(weight) else {
            errorMessage = L10n.string("请输入正确的体重，例如 4.5。")
            return
        }
        let kilograms = RegionalFormat.kilograms(fromDisplayedMass: displayedValue)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let entry {
                    try await store.updateWeightEntry(
                        petID: petID,
                        entryID: entry.id,
                        kilograms: kilograms,
                        measuredAt: measuredAt
                    )
                } else {
                    try await store.addWeightEntry(
                        petID: petID,
                        kilograms: kilograms,
                        measuredAt: measuredAt
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
