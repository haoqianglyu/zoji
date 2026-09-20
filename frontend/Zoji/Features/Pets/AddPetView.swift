import PhotosUI
import SwiftUI
import UIKit

struct PetEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme

    private let pet: Pet?
    private let sharedPet: FamilySharedPet?

    @State private var name: String
    @State private var species: PetSpecies
    @State private var breed: String
    @State private var breedSelection: String
    @State private var sex: PetSex
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var weight: String
    @State private var avatarData: Data?
    @State private var avatarPresetID: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarCropSource: AvatarCropSource?
    @State private var isShowingAvatarLibrary = false
    @State private var isLoadingAvatar = false
    @State private var isSaving = false
    @State private var showsOptionalDetails: Bool
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case breed
        case weight
    }

    private static let customBreedOption = "__custom_breed__"

    init(pet: Pet? = nil, sharedPet: FamilySharedPet? = nil) {
        let initialSpecies = pet?.species ?? .cat
        let initialBreed = pet?.breed ?? ""
        self.pet = pet
        self.sharedPet = sharedPet
        _name = State(initialValue: pet?.name ?? "")
        _species = State(initialValue: initialSpecies)
        _breed = State(initialValue: initialBreed)
        _breedSelection = State(
            initialValue: Self.initialBreedSelection(
                breed: initialBreed,
                species: initialSpecies
            )
        )
        _sex = State(initialValue: pet?.sex ?? .unknown)
        _hasBirthday = State(initialValue: pet?.birthday != nil)
        _birthday = State(initialValue: pet?.birthday ?? Calendar.current.date(byAdding: .year, value: -1, to: Date())!)
        _weight = State(initialValue: pet?.weightKilograms.map(RegionalFormat.massInputString) ?? "")
        _avatarData = State(initialValue: pet?.avatarData)
        _avatarPresetID = State(initialValue: pet?.avatarPresetID)
        _showsOptionalDetails = State(initialValue: pet != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCreatingPet {
                    Section("先认识一下") {
                        compactAvatarEditor
                        nameEditor
                        speciesEditor
                    }

                    Section {
                        DisclosureGroup(isExpanded: $showsOptionalDetails.animation()) {
                            breedEditor
                            optionalInformationEditor
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("完善更多资料", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                                Text("品种、性别、生日和体重都可以稍后填写")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    Section {
                        avatarEditor
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .listRowBackground(Color.clear)
                    }

                    Section("基本资料") {
                        nameEditor
                        speciesEditor
                        breedEditor
                    }

                    Section("更多信息") {
                        optionalInformationEditor
                    }
                }

                Section {
                    Label(
                        sharedPet == nil
                            ? "资料会先保存在这台设备，开启 iCloud 后自动同步。"
                            : "修改会保存到家庭共享的 iCloud 档案，并同步给其他成员。",
                        systemImage: sharedPet == nil ? "iphone.and.arrow.forward" : "person.2.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listSectionSpacing(24)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background)
            .background {
                PetEditorKeyboardDismissTapBridge {
                    focusedField = nil
                }
            }
            .navigationTitle(pet == nil ? "添加宠物" : "编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { savePet() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || isLoadingAvatar)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: selectedPhoto) { _, item in
                loadAvatar(from: item)
            }
            .sheet(isPresented: $isShowingAvatarLibrary) {
                PetAvatarLibraryView(selectedPresetID: avatarPresetID) { preset in
                    selectAvatarPreset(preset)
                }
            }
            .fullScreenCover(item: $avatarCropSource) { source in
                AvatarCropView(image: source.image) { croppedData in
                    avatarData = croppedData
                    avatarPresetID = nil
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "请稍后再试。")
            }
        }
    }

    private var isCreatingPet: Bool {
        pet == nil && sharedPet == nil
    }

    private var nameEditor: some View {
        LabeledContent("名字") {
            TextField("例如：团子", text: $name)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = nil }
                .onChange(of: name) { _, value in
                    name = String(value.prefix(30))
                }
        }
    }

    private var speciesEditor: some View {
        Picker("宠物类型", selection: $species) {
            ForEach(PetSpecies.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: species) { oldSpecies, newSpecies in
            handleSpeciesChange(from: oldSpecies, to: newSpecies)
        }
    }

    @ViewBuilder
    private var optionalInformationEditor: some View {
        Picker("性别", selection: $sex) {
            ForEach(PetSex.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }

        Toggle("记录生日", isOn: $hasBirthday.animation())

        if hasBirthday {
            DatePicker(
                "生日",
                selection: $birthday,
                in: ...Date(),
                displayedComponents: .date
            )
        }

        LabeledContent("体重") {
            HStack(spacing: 6) {
                TextField("选填", text: $weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .weight)
                Text(RegionalFormat.massUnitSymbol)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 150)
        }
    }

    private var compactAvatarEditor: some View {
        HStack(spacing: 14) {
            PetAvatarView(
                avatarData: avatarData,
                avatarPresetID: avatarPresetID,
                fallbackSymbol: species.avatarSymbol,
                size: 62
            )
            .overlay {
                if isLoadingAvatar {
                    ProgressView()
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(hasSelectedAvatar ? "已选择头像" : "头像可稍后添加")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 10) {
                    Button {
                        isShowingAvatarLibrary = true
                    } label: {
                        Label("头像库", systemImage: "square.grid.2x2.fill")
                    }
                    .buttonStyle(.bordered)

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("相册", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    if hasSelectedAvatar {
                        Button(role: .destructive) {
                            avatarData = nil
                            avatarPresetID = nil
                            selectedPhoto = nil
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("移除头像")
                    }
                }
                .font(.caption.weight(.semibold))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .disabled(isLoadingAvatar || isSaving)
    }

    private var avatarEditor: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PetAvatarView(
                    avatarData: avatarData,
                    avatarPresetID: avatarPresetID,
                    fallbackSymbol: species.avatarSymbol,
                    size: 96
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: hasSelectedAvatar ? 3 : 0)
                }

                ZStack {
                    Circle()
                        .fill(theme.accent)
                    if isLoadingAvatar {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 32, height: 32)
                .overlay { Circle().stroke(.background, lineWidth: 3) }
            }

            Text(avatarDisplayName)
                .font(.title2.bold())
                .lineLimit(1)

            HStack(spacing: 12) {
                Button {
                    isShowingAvatarLibrary = true
                } label: {
                    Label("头像库", systemImage: "square.grid.2x2.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(isLoadingAvatar || isSaving)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("相册", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingAvatar || isSaving)

                if hasSelectedAvatar {
                    Button(role: .destructive) {
                        avatarData = nil
                        avatarPresetID = nil
                        selectedPhoto = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingAvatar || isSaving)
                    .accessibilityLabel("移除头像")
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var breedEditor: some View {
        if species == .other {
            LabeledContent("品种") {
                breedTextField(placeholder: "选填")
            }
        } else {
            Picker("品种", selection: $breedSelection) {
                Text("请选择").tag("")
                ForEach(PetBreedCatalog.breeds(for: species), id: \.self) { option in
                    Text(PetBreedCatalog.localizedName(option)).tag(option)
                }
                Text("其他（手动填写）").tag(Self.customBreedOption)
            }
            .pickerStyle(.menu)
            .onChange(of: breedSelection) { _, selection in
                applyBreedSelection(selection)
            }

            if breedSelection == Self.customBreedOption {
                LabeledContent("自定义品种") {
                    breedTextField(placeholder: "请输入")
                }
            }
        }
    }

    private func breedTextField(placeholder: String) -> some View {
        TextField(L10n.dynamic(placeholder), text: $breed)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .focused($focusedField, equals: .breed)
            .onSubmit { focusedField = nil }
            .onChange(of: breed) { _, value in
                breed = String(value.prefix(60))
            }
    }

    private func savePet() {
        let normalizedWeight = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        let weightKilograms: Double?
        if normalizedWeight.isEmpty {
            weightKilograms = nil
        } else if let parsed = RegionalFormat.parseNumber(normalizedWeight) {
            let kilograms = RegionalFormat.kilograms(fromDisplayedMass: parsed)
            guard kilograms > 0, kilograms <= 200 else {
                errorMessage = PetValidationError.weightOutOfRange.localizedDescription
                return
            }
            weightKilograms = kilograms
        } else {
            errorMessage = L10n.string("请输入正确的体重，例如 4.5。")
            return
        }

        focusedField = nil
        isSaving = true
        Task {
            do {
                if let pet, let sharedPet {
                    let trimmedBreed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
                    var weightEntries = pet.weightEntries ?? []
                    if let weightKilograms,
                       pet.weightKilograms.map({
                           !RegionalFormat.representsSameDisplayedMass($0, weightKilograms)
                       }) ?? true {
                        weightEntries.append(
                            WeightEntry(measuredAt: Date(), kilograms: weightKilograms)
                        )
                    }
                    weightEntries.sort { $0.measuredAt < $1.measuredAt }
                    let resolvedWeight = weightKilograms ?? weightEntries.last?.kilograms
                    let updatedPet = Pet(
                        id: pet.id,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        species: species,
                        breed: trimmedBreed.isEmpty ? nil : trimmedBreed,
                        avatarData: avatarData,
                        avatarPresetID: avatarPresetID,
                        sex: sex == .unknown ? nil : sex,
                        birthday: hasBirthday ? birthday : nil,
                        weightKilograms: resolvedWeight,
                        weightEntries: weightEntries,
                        profileStatus: pet.profileStatus
                    )
                    try await familyStore.updatePet(updatedPet, in: sharedPet)
                } else if let pet {
                    try await store.updatePet(
                        id: pet.id,
                        name: name,
                        species: species,
                        breed: breed,
                        sex: sex == .unknown ? nil : sex,
                        birthday: hasBirthday ? birthday : nil,
                        weightKilograms: weightKilograms,
                        avatarData: avatarData,
                        avatarPresetID: avatarPresetID
                    )
                    familyStore.selectPrivatePet()
                } else {
                    try await store.addPet(
                        name: name,
                        species: species,
                        breed: breed,
                        sex: sex == .unknown ? nil : sex,
                        birthday: hasBirthday ? birthday : nil,
                        weightKilograms: weightKilograms,
                        avatarData: avatarData,
                        avatarPresetID: avatarPresetID
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

    private var hasSelectedAvatar: Bool {
        avatarData != nil || avatarPresetID != nil
    }

    private var avatarDisplayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? L10n.string("新伙伴") : trimmedName
    }

    private func selectAvatarPreset(_ preset: PetAvatarPreset) {
        avatarData = nil
        avatarPresetID = preset.id
        selectedPhoto = nil
        species = preset.species
        breed = preset.breed
        breedSelection = preset.breed
    }

    private static func initialBreedSelection(breed: String, species: PetSpecies) -> String {
        let trimmedBreed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBreed.isEmpty else {
            return species == .other ? customBreedOption : ""
        }

        return PetBreedCatalog.breeds(for: species).contains(trimmedBreed)
            ? trimmedBreed
            : customBreedOption
    }

    private func applyBreedSelection(_ selection: String) {
        if selection == Self.customBreedOption {
            if PetBreedCatalog.breeds(for: species).contains(breed) {
                breed = ""
            }
        } else {
            breed = selection
        }
    }

    private func handleSpeciesChange(from oldSpecies: PetSpecies, to newSpecies: PetSpecies) {
        guard oldSpecies != newSpecies else { return }
        clearIncompatibleAvatarPreset(for: newSpecies)

        if let preset = PetAvatarPreset.find(avatarPresetID), preset.species == newSpecies {
            breed = preset.breed
            breedSelection = preset.breed
            return
        }

        breed = ""
        breedSelection = newSpecies == .other ? Self.customBreedOption : ""
    }

    private func clearIncompatibleAvatarPreset(for species: PetSpecies) {
        guard let preset = PetAvatarPreset.find(avatarPresetID),
              preset.species != species
        else { return }

        avatarPresetID = nil
        if breed.trimmingCharacters(in: .whitespacesAndNewlines) == preset.breed {
            breed = ""
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingAvatar = true

        Task {
            defer {
                isLoadingAvatar = false
                selectedPhoto = nil
            }

            do {
                guard let sourceData = try await item.loadTransferable(type: Data.self),
                      let image = await Task.detached(priority: .userInitiated, operation: {
                          AvatarImageProcessor.prepare(sourceData)
                      }).value
                else {
                    errorMessage = L10n.string("无法读取这张照片，请换一张后再试。")
                    return
                }
                focusedField = nil
                avatarCropSource = AvatarCropSource(image: image)
            } catch {
                errorMessage = L10n.string("无法读取这张照片，请换一张后再试。")
            }
        }
    }
}

private struct PetAvatarLibraryView: View {
    @Environment(\.appColorTheme) private var theme

    private enum SpeciesFilter: String, CaseIterable, Identifiable {
        case all
        case cat
        case dog

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "全部"
            case .cat: "猫咪"
            case .dog: "狗狗"
            }
        }

        var species: PetSpecies? {
            switch self {
            case .all: nil
            case .cat: .cat
            case .dog: .dog
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var speciesFilter: SpeciesFilter = .all
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    let selectedPresetID: String?
    let onSelect: (PetAvatarPreset) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filterControls

                    if filteredPresets.isEmpty {
                        emptySearchResult
                    } else {
                        if speciesFilter != .dog {
                            avatarSection(
                                title: "猫咪",
                                presets: filteredPresets.filter { $0.species == .cat }
                            )
                        }
                        if speciesFilter != .cat {
                            avatarSection(
                                title: "狗狗",
                                presets: filteredPresets.filter { $0.species == .dog }
                            )
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background)
            .navigationTitle("默认头像库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var filteredPresets: [PetAvatarPreset] {
        let query = normalized(searchText)

        return PetAvatarPreset.all.filter { preset in
            let matchesSpecies = speciesFilter.species.map { preset.species == $0 } ?? true
            guard matchesSpecies, !query.isEmpty else { return matchesSpecies }

            return ([
                preset.displayName,
                preset.breed,
                preset.localizedDisplayName,
                preset.localizedBreed
            ] + preset.searchAliases + preset.localizedSearchAliases)
                .map(normalized)
                .contains { $0.contains(query) }
        }
    }

    private var filterControls: some View {
        VStack(spacing: 14) {
            Picker("宠物类型", selection: $speciesFilter) {
                ForEach(SpeciesFilter.allCases) { filter in
                    Text(L10n.dynamic(filter.title)).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索品种名称或简称", text: $searchText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private var emptySearchResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text("没有找到匹配的头像")
                .font(.headline)
            Text("可以换一个品种名称或简称试试")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private func avatarSection(title: String, presets: [PetAvatarPreset]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !presets.isEmpty {
                Text(L10n.dynamic(title))
                    .font(.title3.bold())
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(presets) { preset in
                    Button {
                        onSelect(preset)
                        dismiss()
                    } label: {
                        VStack(spacing: 10) {
                            PetAvatarView(
                                avatarData: nil,
                                avatarPresetID: preset.id,
                                fallbackSymbol: preset.species.avatarSymbol,
                                size: 104
                            )
                            .overlay {
                                Circle().stroke(
                                    selectedPresetID == preset.id ? theme.accent : .clear,
                                    lineWidth: 4
                                )
                            }

                            Text(preset.localizedBreed)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .frame(minHeight: 40, alignment: .top)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(
                                    selectedPresetID == preset.id ? theme.accent : Color.secondary.opacity(0.08),
                                    lineWidth: selectedPresetID == preset.id ? 2 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(
                            localized: "使用\(preset.localizedBreed)默认头像",
                            locale: L10n.locale
                        )
                    )
                }
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

/// Adds a non-blocking tap recognizer while the pet editor is visible. Taps on
/// text inputs keep their normal behavior; tapping anywhere else dismisses the
/// keyboard without swallowing buttons, pickers, or other controls.
private struct PetEditorKeyboardDismissTapBridge: UIViewRepresentable {
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

#Preview("添加宠物") {
    PetEditorView()
        .environment(AppStore.preview)
        .environment(FamilySharingStore())
}

#Preview("编辑宠物") {
    PetEditorView(pet: AppStore.preview.pets[0])
        .environment(AppStore.preview)
        .environment(FamilySharingStore())
}
