import Foundation
import Observation

enum InitialCloudRestore {
    static let storageKey = "zoji.initial-cloud-restore.v1"
    static let retryNotification = Notification.Name("zoji.initial-cloud-restore.retry")
}

enum InitialCloudRestorePhase: Equatable {
    case idle
    case checking(restoredPetCount: Int)
    case restoring(restoredPetCount: Int)
    case delayed(restoredPetCount: Int)

    var isVisible: Bool {
        self != .idle
    }

    var restoredPetCount: Int {
        switch self {
        case .idle:
            0
        case .checking(let count), .restoring(let count), .delayed(let count):
            count
        }
    }
}

@MainActor
@Observable
final class AppStore {
    var selectedPetID: UUID?
    var pets: [Pet]
    var reminders: [ReminderItem]
    var records: [HealthRecord]
    var hospitals: [HospitalSummary]
    var petPersistenceMessage: String?
    var recordPersistenceMessage: String?
    var reminderPersistenceMessage: String?
    var notificationPermissionMessage: String?
    var initialCloudRestorePhase = InitialCloudRestorePhase.idle

    @ObservationIgnored private let petRepository: (any PetRepository)?
    @ObservationIgnored private let healthRecordRepository: (any HealthRecordRepository)?
    @ObservationIgnored private let reminderRepository: (any ReminderRepository)?
    @ObservationIgnored private let notificationScheduler: any ReminderNotificationScheduling
    @ObservationIgnored private var hasLoadedPersistedPets = false
    @ObservationIgnored private var hasLoadedPersistedRecords = false
    @ObservationIgnored private var hasLoadedPersistedReminders = false
    @ObservationIgnored private var hasPurgedLegacySoftDeletes = false
    @ObservationIgnored private var familyReloadTask: Task<Void, Never>?

    init(
        selectedPetID: UUID?,
        pets: [Pet],
        reminders: [ReminderItem],
        records: [HealthRecord],
        hospitals: [HospitalSummary],
        petRepository: (any PetRepository)? = nil,
        healthRecordRepository: (any HealthRecordRepository)? = nil,
        reminderRepository: (any ReminderRepository)? = nil,
        notificationScheduler: any ReminderNotificationScheduling = NoOpReminderNotificationScheduler()
    ) {
        self.selectedPetID = selectedPetID
        self.pets = pets
        self.reminders = reminders
        self.records = records
        self.hospitals = hospitals
        self.petRepository = petRepository
        self.healthRecordRepository = healthRecordRepository
        self.reminderRepository = reminderRepository
        self.notificationScheduler = notificationScheduler
    }

    var selectedPet: Pet? {
        pets.first { $0.id == selectedPetID && $0.isActiveProfile }
    }

    var activePets: [Pet] {
        pets.filter(\.isActiveProfile)
    }

    var inactivePets: [Pet] {
        pets.filter { !$0.isActiveProfile }
    }

    func selectedPet(using familyStore: FamilySharingStore) -> SelectedPet? {
        if let sharedPet = familyStore.selectedSharedPet,
           sharedPet.pet.isActiveProfile {
            return .shared(sharedPet)
        }
        guard let selectedPet else { return nil }
        return localSelection(for: selectedPet)
    }

    func selectablePets(using familyStore: FamilySharingStore) -> [SelectedPet] {
        activePets.map { localSelection(for: $0) }
            + familyStore.sharedPets.filter { $0.pet.isActiveProfile }.map { .shared($0) }
    }

    func select(_ selection: SelectedPet, using familyStore: FamilySharingStore) {
        switch selection {
        case .local(let pet, _, _):
            selectedPetID = pet.id
            familyStore.selectPrivatePet()
        case .shared(let sharedPet):
            familyStore.selectedSharedPetID = sharedPet.id
        }
    }

    private func localSelection(for pet: Pet) -> SelectedPet {
        .local(
            pet: pet,
            records: records.filter { $0.petID == pet.id },
            reminders: reminders.filter { $0.petID == pet.id }
        )
    }

    func rescheduleNotificationsForCurrentLanguage() async {
        let activePetIDs = Set(activePets.map(\.id))
        for reminder in reminders where reminder.isEnabled && activePetIDs.contains(reminder.petID) {
            let petName = pets.first(where: { $0.id == reminder.petID })?.name ?? L10n.string("宠物")
            try? await notificationScheduler.replaceNotifications(for: reminder, petName: petName)
        }
    }

    func makeBackupArchive() async throws -> ZojiBackupArchive {
        var completeRecords: [HealthRecord] = []
        for pet in pets {
            completeRecords.append(contentsOf: try await recordsWithAttachmentData(petID: pet.id))
        }
        return ZojiBackupArchive(
            selectedPetID: selectedPetID,
            pets: pets,
            records: completeRecords,
            reminders: reminders
        )
    }

    func healthRecordWithAttachments(id: UUID) async throws -> HealthRecord? {
        if let healthRecordRepository {
            return try await healthRecordRepository.record(id: id)
        }
        return records.first { $0.id == id }
    }

    func familySharePayload(for pet: Pet) async throws -> FamilyPetSharePayload {
        FamilyPetSharePayload(
            pet: pet,
            records: try await recordsWithAttachmentData(petID: pet.id),
            reminders: reminders
        )
    }

    func familySharePayloads() async throws -> [FamilyPetSharePayload] {
        var payloads: [FamilyPetSharePayload] = []
        for pet in pets {
            payloads.append(try await familySharePayload(for: pet))
        }
        return payloads
    }

    func importBackupArchive(_ archive: ZojiBackupArchive) async throws {
        try archive.validate()

        for pet in archive.pets {
            try await petRepository?.save(pet)
        }
        for record in archive.records {
            try await healthRecordRepository?.save(record)
        }
        for reminder in archive.reminders {
            try await reminderRepository?.save(reminder)
        }

        await reloadPersistedData()
        if let selectedPetID = archive.selectedPetID,
           pets.contains(where: { $0.id == selectedPetID }) {
            self.selectedPetID = selectedPetID
        }
    }

    /// Keeps the owner's local-first SwiftData mirror aligned with the records
    /// edited by family members in the owner's shared CloudKit zone.
    func applyOwnedFamilyPayload(_ payload: FamilyPetSharePayload) async throws {
        try payload.validate()
        let petID = payload.pet.id
        try await petRepository?.save(payload.pet)
        if let index = pets.firstIndex(where: { $0.id == petID }) {
            pets[index] = payload.pet
        } else {
            pets.append(payload.pet)
        }

        let incomingRecordIDs = Set(payload.records.map(\.id))
        for record in records where record.petID == petID && !incomingRecordIDs.contains(record.id) {
            try await healthRecordRepository?.delete(recordID: record.id)
        }
        for record in payload.records {
            try await healthRecordRepository?.save(record)
        }

        let incomingReminderIDs = Set(payload.reminders.map(\.id))
        for reminder in reminders where reminder.petID == petID && !incomingReminderIDs.contains(reminder.id) {
            try await reminderRepository?.delete(reminderID: reminder.id)
            await notificationScheduler.removeNotifications(reminderID: reminder.id)
        }
        for reminder in payload.reminders {
            try await reminderRepository?.save(reminder)
            if reminder.isEnabled {
                await scheduleNotifications(for: reminder, requestingAuthorization: false)
            } else {
                await notificationScheduler.removeNotifications(reminderID: reminder.id)
            }
        }

        records.removeAll { $0.petID == petID }
        records.append(contentsOf: payload.records.map(Self.withoutAttachmentData))
        reminders.removeAll { $0.petID == petID }
        reminders.append(contentsOf: payload.reminders)
    }

    func reloadPersistedData() async {
        await purgeLegacySoftDeletesIfNeeded()
        hasLoadedPersistedPets = false
        hasLoadedPersistedRecords = false
        hasLoadedPersistedReminders = false
        await loadPersistedPetsIfNeeded()
        await loadPersistedRecordsIfNeeded()
        await loadPersistedRemindersIfNeeded()
    }

    private func purgeLegacySoftDeletesIfNeeded() async {
        guard !hasPurgedLegacySoftDeletes else { return }
        do {
            try await healthRecordRepository?.purgeLegacySoftDeletedEntities()
            try await reminderRepository?.purgeLegacySoftDeletedEntities()
            try await petRepository?.purgeLegacySoftDeletedEntities()
            hasPurgedLegacySoftDeletes = true
        } catch {
            recordPersistenceMessage = String(localized: "清理旧版已删除数据失败：\(error.localizedDescription)", locale: L10n.locale)
        }
    }

    /// Reloads the local SwiftData mirror and reconciles both directions of
    /// family sharing. App launch, foreground refresh, and the Home pull gesture
    /// use this same path so they cannot drift into different sync behavior.
    func reloadPersistedAndFamilyData(using familyStore: FamilySharingStore) async {
        if let familyReloadTask {
            await familyReloadTask.value
            return
        }
        let task = Task { @MainActor [weak self, weak familyStore] in
            guard let self, let familyStore else { return }
            await self.performPersistedAndFamilyReload(using: familyStore)
        }
        familyReloadTask = task
        await task.value
        familyReloadTask = nil
    }

    private func performPersistedAndFamilyReload(using familyStore: FamilySharingStore) async {
        await reloadPersistedData()
        familyStore.resolveLaunchSelection(hasPrivatePets: !activePets.isEmpty)
        guard PersistenceController.isCloudKitConfigured else { return }

        let payloads: [FamilyPetSharePayload]
        do {
            payloads = try await familySharePayloads()
        } catch {
            recordPersistenceMessage = String(localized: "读取共享附件失败：\(error.localizedDescription)", locale: L10n.locale)
            return
        }
        await familyStore.refresh(privatePayloads: payloads)

        for ownedSharedPet in familyStore.ownedSharedPets {
            do {
                try await applyOwnedFamilyPayload(ownedSharedPet.payload)
            } catch {
                recordPersistenceMessage = String(localized: "家庭共享数据已读取，但暂时无法更新本机副本：\(error.localizedDescription)", locale: L10n.locale)
            }
        }
    }

    func loadPersistedPetsIfNeeded() async {
        guard !hasLoadedPersistedPets, let petRepository else { return }

        do {
            pets = try await petRepository.listPets()
            if !pets.contains(where: { $0.id == selectedPetID && $0.isActiveProfile }) {
                selectedPetID = activePets.first?.id
            }
            hasLoadedPersistedPets = true
        } catch {
            petPersistenceMessage = L10n.string("读取宠物资料失败，请重新打开 App 后再试。")
        }
    }

    func loadPersistedRecordsIfNeeded() async {
        guard !hasLoadedPersistedRecords, let healthRecordRepository else { return }

        do {
            var persistedRecords: [HealthRecord] = []
            for pet in pets {
                persistedRecords.append(contentsOf: try await healthRecordRepository.listRecords(petID: pet.id))
            }
            records = persistedRecords
            hasLoadedPersistedRecords = true
        } catch {
            recordPersistenceMessage = L10n.string("读取健康记录失败，请稍后重试。")
        }
    }

    func loadPersistedRemindersIfNeeded() async {
        guard !hasLoadedPersistedReminders, let reminderRepository else { return }

        do {
            var persistedReminders: [ReminderItem] = []
            for pet in pets {
                persistedReminders.append(contentsOf: try await reminderRepository.listReminders(petID: pet.id))
            }
            reminders = persistedReminders
            hasLoadedPersistedReminders = true

            for reminder in reminders where reminder.isEnabled {
                if let petName = pets.first(where: { $0.id == reminder.petID })?.name {
                    try? await notificationScheduler.replaceNotifications(for: reminder, petName: petName)
                }
            }
        } catch {
            reminderPersistenceMessage = L10n.string("读取提醒失败，请稍后重试。")
        }
    }

    func addPet(
        name: String,
        species: PetSpecies,
        breed: String?,
        sex: PetSex?,
        birthday: Date?,
        weightKilograms: Double?,
        avatarData: Data? = nil,
        avatarPresetID: String? = nil
    ) async throws {
        let initialWeightEntries = weightKilograms.map {
            [WeightEntry(measuredAt: Date(), kilograms: $0)]
        }
        let pet = try validatedPet(
            id: UUID(),
            name: name,
            species: species,
            breed: breed,
            sex: sex,
            birthday: birthday,
            weightKilograms: weightKilograms,
            weightEntries: initialWeightEntries,
            avatarData: avatarData,
            avatarPresetID: avatarPresetID
        )

        try await petRepository?.save(pet)
        pets.append(pet)
        selectedPetID = pet.id
    }

    func updatePet(
        id: UUID,
        name: String,
        species: PetSpecies,
        breed: String?,
        sex: PetSex?,
        birthday: Date?,
        weightKilograms: Double?,
        avatarData: Data? = nil,
        avatarPresetID: String? = nil
    ) async throws {
        guard let index = pets.firstIndex(where: { $0.id == id }) else { return }
        let originalPet = pets[index]
        var weightEntries = originalPet.weightEntries ?? []
        if let weightKilograms,
           originalPet.weightKilograms.map({
               !RegionalFormat.representsSameDisplayedMass($0, weightKilograms)
           }) ?? true {
            weightEntries.append(WeightEntry(measuredAt: Date(), kilograms: weightKilograms))
        }
        let resolvedWeight = weightKilograms ?? weightEntries.max(by: { $0.measuredAt < $1.measuredAt })?.kilograms
        let pet = try validatedPet(
            id: id,
            name: name,
            species: species,
            breed: breed,
            sex: sex,
            birthday: birthday,
            weightKilograms: resolvedWeight,
            weightEntries: weightEntries,
            avatarData: avatarData,
            avatarPresetID: avatarPresetID,
            profileStatus: originalPet.profileStatus
        )

        try await petRepository?.save(pet)
        pets[index] = pet
        if let location = await FamilySharingService.shared.ownedMutationLocation(for: id) {
            try? await FamilySharingLocalStore.shared.upsertCachedOwnedPet(pet, location: location)
            await enqueueFamilyChange(.save(pet, replacing: originalPet, at: location))
        }
    }

    func setPetProfileStatus(id: UUID, status: PetProfileStatus) async throws {
        guard let index = pets.firstIndex(where: { $0.id == id }) else {
            throw WeightEntryValidationError.petNotFound
        }
        let originalPet = pets[index]
        var pet = originalPet
        pet.profileStatus = status == .active ? nil : status

        try await petRepository?.save(pet)
        pets[index] = pet

        let petReminders = reminders.filter { $0.petID == id }
        if status.isActive {
            for reminder in petReminders where reminder.isEnabled {
                await scheduleNotifications(for: reminder, requestingAuthorization: false)
            }
        } else {
            for reminder in petReminders {
                await notificationScheduler.removeNotifications(reminderID: reminder.id)
            }
            if selectedPetID == id {
                selectedPetID = activePets.first?.id
            }
        }

        if let location = await FamilySharingService.shared.ownedMutationLocation(for: id) {
            try? await FamilySharingLocalStore.shared.upsertCachedOwnedPet(pet, location: location)
            await enqueueFamilyChange(.save(pet, replacing: originalPet, at: location))
        }
    }

    func addWeightEntry(petID: UUID, kilograms: Double, measuredAt: Date) async throws {
        guard let index = pets.firstIndex(where: { $0.id == petID }) else {
            throw WeightEntryValidationError.petNotFound
        }
        try validateWeightEntry(kilograms: kilograms, measuredAt: measuredAt)

        let originalPet = pets[index]
        var pet = originalPet
        var entries = pet.weightEntries ?? []
        entries.append(WeightEntry(measuredAt: measuredAt, kilograms: kilograms))
        pet.weightEntries = entries.sorted { $0.measuredAt < $1.measuredAt }
        pet.weightKilograms = pet.sortedWeightEntries.last?.kilograms
        try await persistUpdatedPet(pet, replacing: originalPet, at: index)
    }

    func updateWeightEntry(
        petID: UUID,
        entryID: UUID,
        kilograms: Double,
        measuredAt: Date
    ) async throws {
        guard let index = pets.firstIndex(where: { $0.id == petID }) else {
            throw WeightEntryValidationError.petNotFound
        }
        try validateWeightEntry(kilograms: kilograms, measuredAt: measuredAt)

        let originalPet = pets[index]
        var pet = originalPet
        guard var entries = pet.weightEntries,
              let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            throw WeightEntryValidationError.entryNotFound
        }
        entries[entryIndex].kilograms = kilograms
        entries[entryIndex].measuredAt = measuredAt
        pet.weightEntries = entries.sorted { $0.measuredAt < $1.measuredAt }
        pet.weightKilograms = pet.sortedWeightEntries.last?.kilograms
        try await persistUpdatedPet(pet, replacing: originalPet, at: index)
    }

    func deleteWeightEntry(petID: UUID, entryID: UUID) async throws {
        guard let index = pets.firstIndex(where: { $0.id == petID }) else {
            throw WeightEntryValidationError.petNotFound
        }
        let originalPet = pets[index]
        var pet = originalPet
        pet.weightEntries?.removeAll { $0.id == entryID }
        pet.weightKilograms = pet.sortedWeightEntries.last?.kilograms
        try await persistUpdatedPet(pet, replacing: originalPet, at: index)
    }

    func deletePet(id: UUID) async throws {
        let deletedPet = pets.first { $0.id == id }
        let familyLocation: FamilyShareLocation? = if deletedPet != nil {
            await FamilySharingService.shared.ownedMutationLocation(for: id)
        } else { nil }
        let deletionChange: FamilyPendingChange? = if let deletedPet, let familyLocation {
            FamilyPendingChange.delete(deletedPet, at: familyLocation)
        } else { nil }

        // A shared pet loses its last owner-side UI entry after deletion. Store
        // the CloudKit deletion in the durable outbox before removing that entry,
        // otherwise an outbox write failure would leave an unreachable zombie
        // share in every family member's app.
        if let deletionChange {
            try await FamilySharingLocalStore.shared.enqueue(deletionChange)
        }
        do {
            for reminder in reminders where reminder.petID == id {
                await notificationScheduler.removeNotifications(reminderID: reminder.id)
            }
            try await reminderRepository?.deleteAll(petID: id)
            try await healthRecordRepository?.deleteAll(petID: id)
            try await petRepository?.delete(petID: id)
        } catch {
            if let deletionChange {
                try? await FamilySharingLocalStore.shared.markCompleted(deletionChange.id)
            }
            throw error
        }
        pets.removeAll { $0.id == id }
        reminders.removeAll { $0.petID == id }
        records.removeAll { $0.petID == id }
        if selectedPetID == id {
            selectedPetID = pets.first?.id
        }
        if deletionChange != nil {
            NotificationCenter.default.post(
                name: FamilySharingService.pendingChangesDidUpdateNotification,
                object: nil
            )
        }
    }

    @discardableResult
    func addHealthRecord(
        petID: UUID,
        kind: RecordKind,
        title: String,
        occurredAt: Date,
        providerName: String?,
        costCents: Int?,
        currencyCode: String? = nil,
        notes: String? = nil,
        attachments: [HealthRecordAttachment] = []
    ) async throws -> HealthRecord {
        let record = try validatedHealthRecord(
            id: UUID(),
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

        try await healthRecordRepository?.save(record)
        records.append(Self.withoutAttachmentData(record))
        selectedPetID = petID
        if let location = await FamilySharingService.shared.ownedMutationLocation(for: petID) {
            await enqueueFamilyChange(.save(record, at: location))
        }
        return record
    }

    func updateHealthRecord(
        id: UUID,
        kind: RecordKind,
        title: String,
        occurredAt: Date,
        providerName: String?,
        costCents: Int?,
        currencyCode: String? = nil,
        notes: String? = nil,
        attachments: [HealthRecordAttachment] = []
    ) async throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let originalRecord = try await healthRecordRepository?.record(id: id) ?? records[index]
        let record = try validatedHealthRecord(
            id: id,
            petID: originalRecord.petID,
            kind: kind,
            title: title,
            occurredAt: occurredAt,
            providerName: providerName,
            costCents: costCents,
            currencyCode: currencyCode,
            timeZoneIdentifier: originalRecord.timeZoneIdentifier,
            notes: notes,
            attachments: attachments
        )

        try await healthRecordRepository?.save(record)
        records[index] = Self.withoutAttachmentData(record)
        if let location = await FamilySharingService.shared.ownedMutationLocation(for: record.petID) {
            await enqueueFamilyChange(.save(record, replacing: originalRecord, at: location))
        }
    }

    func deleteHealthRecord(id: UUID) async throws {
        let deletedRecord = records.first { $0.id == id }
        let linkedReminders = reminders.filter { $0.sourceRecordID == id }
        let familyLocation: FamilyShareLocation? = if let deletedRecord {
            await FamilySharingService.shared.ownedMutationLocation(for: deletedRecord.petID)
        } else { nil }
        for reminder in linkedReminders {
            try await reminderRepository?.delete(reminderID: reminder.id)
            await notificationScheduler.removeNotifications(reminderID: reminder.id)
        }
        try await healthRecordRepository?.delete(recordID: id)
        reminders.removeAll { $0.sourceRecordID == id }
        records.removeAll { $0.id == id }
        if let deletedRecord, let familyLocation {
            await enqueueFamilyChange(.delete(deletedRecord, at: familyLocation))
            for reminder in linkedReminders {
                await enqueueFamilyChange(.delete(reminder, at: familyLocation))
            }
        }
    }

    func addReminder(
        petID: UUID,
        sourceRecordID: UUID? = nil,
        title: String,
        kind: RecordKind,
        dueAt: Date,
        scheduleType: ScheduleType,
        intervalValue: Int?,
        advanceDays: [Int]
    ) async throws {
        let reminder = try validatedReminder(
            id: UUID(),
            petID: petID,
            sourceRecordID: sourceRecordID,
            title: title,
            kind: kind,
            dueAt: dueAt,
            scheduleType: scheduleType,
            intervalValue: intervalValue,
            advanceDays: advanceDays,
            isEnabled: true,
            lastCompletedAt: nil
        )

        try await reminderRepository?.save(reminder)
        reminders.append(reminder)
        selectedPetID = petID
        await scheduleNotifications(for: reminder, requestingAuthorization: true)
        if let location = await FamilySharingService.shared.ownedMutationLocation(for: petID) {
            await enqueueFamilyChange(.save(reminder, at: location))
        }
    }

    @discardableResult
    func addCarePlan(
        petID: UUID,
        template: CarePlanTemplate,
        startDate: Date,
        notificationTime: Date,
        selectedStepIDs: Set<String>
    ) async throws -> Int {
        guard let pet = pets.first(where: { $0.id == petID && $0.isActiveProfile }) else {
            throw ReminderValidationError.petNotFound
        }
        guard pet.species == template.species else {
            throw ReminderValidationError.templateSpeciesMismatch
        }

        let selectedSteps = template.steps.filter { selectedStepIDs.contains($0.id) }
        guard !selectedSteps.isEmpty else {
            throw ReminderValidationError.planStepsRequired
        }

        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let notificationTimeComponents = calendar.dateComponents([.hour, .minute], from: notificationTime)
        var newReminders: [ReminderItem] = []
        for step in selectedSteps {
            let dueDate = calendar.startOfDay(for: step.dueDate(from: normalizedStartDate, calendar: calendar))
            let dueAt = calendar.date(
                bySettingHour: notificationTimeComponents.hour ?? 0,
                minute: notificationTimeComponents.minute ?? 0,
                second: 0,
                of: dueDate
            ) ?? dueDate
            let isDuplicate = reminders.contains { reminder in
                reminder.petID == petID
                    && reminder.isEnabled
                    && reminder.kind == step.kind
                    && reminder.title == step.title
                    && calendar.isDate(reminder.dueAt, inSameDayAs: dueAt)
            }
            guard !isDuplicate else { continue }

            newReminders.append(try validatedReminder(
                id: UUID(),
                petID: petID,
                sourceRecordID: nil,
                title: step.title,
                kind: step.kind,
                dueAt: dueAt,
                scheduleType: step.scheduleType,
                intervalValue: step.intervalValue,
                advanceDays: step.advanceDays,
                isEnabled: true,
                lastCompletedAt: nil
            ))
        }

        guard !newReminders.isEmpty else {
            throw ReminderValidationError.planAlreadyExists
        }

        var persistedReminderIDs: [UUID] = []
        do {
            for reminder in newReminders {
                try await reminderRepository?.save(reminder)
                persistedReminderIDs.append(reminder.id)
            }
        } catch {
            for reminderID in persistedReminderIDs {
                try? await reminderRepository?.delete(reminderID: reminderID)
            }
            throw error
        }

        reminders.append(contentsOf: newReminders)
        selectedPetID = petID

        if let location = await FamilySharingService.shared.ownedMutationLocation(for: petID) {
            for reminder in newReminders {
                await enqueueFamilyChange(.save(reminder, at: location))
            }
        }

        let isAuthorized = await notificationScheduler.requestAuthorization()
        if isAuthorized {
            for reminder in newReminders {
                do {
                    try await notificationScheduler.replaceNotifications(for: reminder, petName: pet.name)
                } catch {
                    reminderPersistenceMessage = L10n.string("计划已保存，但部分系统通知安排失败，请稍后再试。")
                    break
                }
            }
        } else {
            notificationPermissionMessage = L10n.string("计划已保存，但系统通知尚未开启。可稍后到 iPhone 设置中允许 Zoji 通知。")
        }

        return newReminders.count
    }

    func updateReminder(
        id: UUID,
        petID: UUID,
        title: String,
        kind: RecordKind,
        dueAt: Date,
        scheduleType: ScheduleType,
        intervalValue: Int?,
        advanceDays: [Int]
    ) async throws {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let originalReminder = reminders[index]
        let reminder = try validatedReminder(
            id: id,
            petID: petID,
            sourceRecordID: originalReminder.sourceRecordID,
            title: title,
            kind: kind,
            dueAt: dueAt,
            scheduleType: scheduleType,
            intervalValue: intervalValue,
            advanceDays: advanceDays,
            isEnabled: true,
            lastCompletedAt: originalReminder.lastCompletedAt
        )

        try await reminderRepository?.save(reminder)
        reminders[index] = reminder
        selectedPetID = petID
        await scheduleNotifications(for: reminder, requestingAuthorization: true)
        if let location = await FamilySharingService.shared.ownedMutationLocation(for: petID) {
            await enqueueFamilyChange(.save(reminder, replacing: originalReminder, at: location))
        }
    }

    @discardableResult
    func completeReminder(id: UUID) async throws -> Date? {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return nil }
        let originalReminder = reminders[index]
        guard !originalReminder.isCompletionLocked() else {
            throw ReminderCompletionError.currentCycleAlreadyCompleted
        }
        var reminder = reminders[index]
        let completedAt = Date()
        reminder.lastCompletedAt = completedAt
        let nextDueAt: Date?

        if let calculatedDueAt = ReminderCalculator.nextDueDate(
            after: completedAt,
            scheduleType: reminder.scheduleType,
            intervalValue: reminder.intervalValue,
            preservingTimeFrom: reminder.dueAt
        ) {
            nextDueAt = calculatedDueAt
            reminder.dueAt = calculatedDueAt
            reminder.isEnabled = true
        } else {
            nextDueAt = nil
            reminder.isEnabled = false
        }

        let completionRecord = try validatedHealthRecord(
            id: UUID(),
            petID: reminder.petID,
            kind: reminder.kind,
            title: reminder.title,
            occurredAt: completedAt,
            providerName: nil,
            costCents: nil,
            notes: HealthRecord.reminderCompletionNoteMarker,
            attachments: []
        )

        // Optimistically update the UI so the completion action feels immediate.
        reminders[index] = reminder
        var didPersistCompletionRecord = false
        do {
            try await healthRecordRepository?.save(completionRecord)
            didPersistCompletionRecord = healthRecordRepository != nil
            try await reminderRepository?.save(reminder)
        } catch {
            if didPersistCompletionRecord {
                try? await healthRecordRepository?.delete(recordID: completionRecord.id)
            }
            if let rollbackIndex = reminders.firstIndex(where: { $0.id == id }) {
                reminders[rollbackIndex] = originalReminder
            }
            throw error
        }
        records.append(completionRecord)
        if reminder.isEnabled {
            await scheduleNotifications(for: reminder, requestingAuthorization: false)
        } else {
            await notificationScheduler.removeNotifications(reminderID: reminder.id)
        }
        if let location = await FamilySharingService.shared.ownedMutationLocation(
            for: originalReminder.petID
        ) {
            await enqueueFamilyChange(.complete(
                reminder,
                replacing: originalReminder,
                record: completionRecord,
                at: location
            ))
        }
        return nextDueAt
    }

    func deleteReminder(id: UUID) async throws {
        let deletedReminder = reminders.first { $0.id == id }
        let familyLocation: FamilyShareLocation? = if let deletedReminder {
            await FamilySharingService.shared.ownedMutationLocation(for: deletedReminder.petID)
        } else { nil }
        try await reminderRepository?.delete(reminderID: id)
        await notificationScheduler.removeNotifications(reminderID: id)
        reminders.removeAll { $0.id == id }
        if let deletedReminder, let familyLocation {
            await enqueueFamilyChange(.delete(deletedReminder, at: familyLocation))
        }
    }

    private func enqueueFamilyChange(_ change: FamilyPendingChange) async {
        do {
            try await FamilySharingLocalStore.shared.enqueue(change)
            NotificationCenter.default.post(
                name: FamilySharingService.pendingChangesDidUpdateNotification,
                object: nil
            )
        } catch {
            recordPersistenceMessage = String(localized: "修改已保存在本机，但暂时无法加入 iCloud 同步队列：\(error.localizedDescription)", locale: L10n.locale)
        }
    }

    private func recordsWithAttachmentData(petID: UUID) async throws -> [HealthRecord] {
        if let healthRecordRepository {
            return try await healthRecordRepository.listRecords(
                petID: petID,
                includingAttachmentData: true
            )
        }
        return records.filter { $0.petID == petID }
    }

    private static func withoutAttachmentData(_ record: HealthRecord) -> HealthRecord {
        var lightweight = record
        for index in lightweight.attachments.indices {
            lightweight.attachments[index].data = Data()
        }
        return lightweight
    }

    private func validatedPet(
        id: UUID,
        name: String,
        species: PetSpecies,
        breed: String?,
        sex: PetSex?,
        birthday: Date?,
        weightKilograms: Double?,
        weightEntries: [WeightEntry]? = nil,
        avatarData: Data?,
        avatarPresetID: String?,
        profileStatus: PetProfileStatus? = nil
    ) throws -> Pet {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PetValidationError.nameRequired
        }
        if let birthday, birthday > Date() {
            throw PetValidationError.birthdayInFuture
        }
        if let weightKilograms, weightKilograms <= 0 || weightKilograms > 200 {
            throw PetValidationError.weightOutOfRange
        }

        let trimmedBreed = breed?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Pet(
            id: id,
            name: trimmedName,
            species: species,
            breed: trimmedBreed?.isEmpty == false ? trimmedBreed : nil,
            avatarData: avatarData,
            avatarPresetID: avatarPresetID,
            sex: sex,
            birthday: birthday,
            weightKilograms: weightKilograms,
            weightEntries: weightEntries,
            profileStatus: profileStatus
        )
    }

    private func validateWeightEntry(kilograms: Double, measuredAt: Date) throws {
        guard kilograms > 0, kilograms <= 200 else {
            throw WeightEntryValidationError.weightOutOfRange
        }
        guard measuredAt <= Date() else {
            throw WeightEntryValidationError.dateInFuture
        }
    }

    private func persistUpdatedPet(_ pet: Pet, replacing basePet: Pet, at index: Int) async throws {
        try await petRepository?.save(pet)
        pets[index] = pet
        if let location = await FamilySharingService.shared.ownedMutationLocation(for: pet.id) {
            try? await FamilySharingLocalStore.shared.upsertCachedOwnedPet(pet, location: location)
            await enqueueFamilyChange(.save(pet, replacing: basePet, at: location))
        }
    }

    private func validatedHealthRecord(
        id: UUID,
        petID: UUID,
        kind: RecordKind,
        title: String,
        occurredAt: Date,
        providerName: String?,
        costCents: Int?,
        currencyCode: String? = nil,
        timeZoneIdentifier: String? = TimeZone.autoupdatingCurrent.identifier,
        notes: String?,
        attachments: [HealthRecordAttachment]
    ) throws -> HealthRecord {
        guard pets.contains(where: { $0.id == petID && $0.isActiveProfile }) else {
            throw HealthRecordValidationError.petNotFound
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw HealthRecordValidationError.titleRequired
        }
        guard occurredAt <= Date() else {
            throw HealthRecordValidationError.dateInFuture
        }
        let normalizedCurrencyCode = RegionalFormat.normalizedCurrencyCode(currencyCode ?? "CNY")
        if let costCents,
           costCents < 0 || costCents > RegionalFormat.maximumMinorUnits(code: normalizedCurrencyCode) {
            throw HealthRecordValidationError.costOutOfRange
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNotes, trimmedNotes.count > 5_000 {
            throw HealthRecordValidationError.detailsTooLong
        }
        try HealthRecordAttachmentPolicy.validate(attachments)

        let trimmedProvider = providerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return HealthRecord(
            id: id,
            petID: petID,
            kind: kind,
            title: trimmedTitle,
            occurredAt: occurredAt,
            providerName: trimmedProvider?.isEmpty == false ? trimmedProvider : nil,
            costCents: costCents,
            currencyCode: costCents == nil ? nil : normalizedCurrencyCode,
            timeZoneIdentifier: timeZoneIdentifier,
            notes: trimmedNotes?.isEmpty == false ? trimmedNotes : nil,
            attachments: attachments
        )
    }

    private func validatedReminder(
        id: UUID,
        petID: UUID,
        sourceRecordID: UUID?,
        title: String,
        kind: RecordKind,
        dueAt: Date,
        scheduleType: ScheduleType,
        intervalValue: Int?,
        advanceDays: [Int],
        isEnabled: Bool,
        lastCompletedAt: Date?
    ) throws -> ReminderItem {
        guard pets.contains(where: { $0.id == petID && $0.isActiveProfile }) else {
            throw ReminderValidationError.petNotFound
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ReminderValidationError.titleRequired
        }
        guard dueAt >= Calendar.current.startOfDay(for: Date()) else {
            throw ReminderValidationError.dateInPast
        }
        if scheduleType != .oneOff {
            guard let intervalValue, (1 ... 3650).contains(intervalValue) else {
                throw ReminderValidationError.invalidInterval
            }
        }
        let normalizedAdvanceDays = Array(Set(advanceDays)).sorted(by: >)
        guard !normalizedAdvanceDays.isEmpty,
              normalizedAdvanceDays.allSatisfy({ (0 ... 30).contains($0) }) else {
            throw ReminderValidationError.invalidAdvanceDays
        }

        return ReminderItem(
            id: id,
            petID: petID,
            sourceRecordID: sourceRecordID,
            title: trimmedTitle,
            kind: kind,
            dueAt: dueAt,
            scheduleType: scheduleType,
            intervalValue: scheduleType == .oneOff ? nil : intervalValue,
            advanceDays: normalizedAdvanceDays,
            isEnabled: isEnabled,
            lastCompletedAt: lastCompletedAt
        )
    }

    private func scheduleNotifications(for reminder: ReminderItem, requestingAuthorization: Bool) async {
        guard let pet = pets.first(where: { $0.id == reminder.petID }),
              pet.isActiveProfile else {
            await notificationScheduler.removeNotifications(reminderID: reminder.id)
            return
        }
        if requestingAuthorization {
            let isAuthorized = await notificationScheduler.requestAuthorization()
            if !isAuthorized {
                notificationPermissionMessage = L10n.string("提醒已保存，但系统通知尚未开启。可稍后到 iPhone 设置中允许 Zoji 通知。")
                return
            }
        }
        do {
            try await notificationScheduler.replaceNotifications(for: reminder, petName: pet.name)
        } catch {
            reminderPersistenceMessage = L10n.string("提醒已保存，但系统通知安排失败，请稍后再试。")
        }
    }
}

enum PetValidationError: LocalizedError {
    case nameRequired
    case birthdayInFuture
    case weightOutOfRange

    var errorDescription: String? {
        switch self {
        case .nameRequired: L10n.string("请填写宠物名字。")
        case .birthdayInFuture: L10n.string("生日不能晚于今天。")
        case .weightOutOfRange:
            RegionalFormat.usesPounds
                ? L10n.string("请输入 0 到 440 磅之间的体重。")
                : L10n.string("请输入 0 到 200 千克之间的体重。")
        }
    }
}

enum WeightEntryValidationError: LocalizedError {
    case petNotFound
    case entryNotFound
    case weightOutOfRange
    case dateInFuture

    var errorDescription: String? {
        switch self {
        case .petNotFound: L10n.string("找不到这份宠物档案。")
        case .entryNotFound: L10n.string("找不到这条体重记录。")
        case .weightOutOfRange:
            RegionalFormat.usesPounds
                ? L10n.string("请输入 0 到 440 磅之间的体重。")
                : L10n.string("请输入 0 到 200 千克之间的体重。")
        case .dateInFuture: L10n.string("称重日期不能晚于今天。")
        }
    }
}

enum HealthRecordValidationError: LocalizedError {
    case petNotFound
    case titleRequired
    case dateInFuture
    case costOutOfRange
    case detailsTooLong

    var errorDescription: String? {
        switch self {
        case .petNotFound: L10n.string("请先选择宠物。")
        case .titleRequired: L10n.string("请填写记录名称。")
        case .dateInFuture: L10n.string("记录日期不能晚于今天。")
        case .costOutOfRange: L10n.string("费用应在 0 到 100 万之间。")
        case .detailsTooLong: L10n.string("详情请控制在 5000 个字以内。")
        }
    }
}

enum ReminderValidationError: LocalizedError {
    case petNotFound
    case titleRequired
    case dateInPast
    case invalidInterval
    case invalidAdvanceDays
    case templateSpeciesMismatch
    case planStepsRequired
    case planAlreadyExists

    var errorDescription: String? {
        switch self {
        case .petNotFound: L10n.string("请先选择宠物。")
        case .titleRequired: L10n.string("请填写提醒名称。")
        case .dateInPast: L10n.string("提醒日期不能早于今天。")
        case .invalidInterval: L10n.string("请选择有效的重复周期。")
        case .invalidAdvanceDays: L10n.string("请至少选择一个提前通知日期。")
        case .templateSpeciesMismatch: L10n.string("这套计划不适用于当前宠物类型。")
        case .planStepsRequired: L10n.string("请至少选择一个计划项目。")
        case .planAlreadyExists: L10n.string("所选项目已经在提醒列表中，无需重复添加。")
        }
    }
}

enum ReminderCompletionError: LocalizedError {
    case currentCycleAlreadyCompleted

    var errorDescription: String? {
        switch self {
        case .currentCycleAlreadyCompleted:
            L10n.string("本周期已经完成，下次到期后才能再次记录。")
        }
    }
}

extension AppStore {
    static var preview: AppStore {
        makePreview()
    }

    static func live(
        petRepository: any PetRepository,
        healthRecordRepository: (any HealthRecordRepository)? = nil,
        reminderRepository: (any ReminderRepository)? = nil,
        notificationScheduler: any ReminderNotificationScheduling = NoOpReminderNotificationScheduler()
    ) -> AppStore {
        AppStore(
            selectedPetID: nil,
            pets: [],
            reminders: [],
            records: [],
            hospitals: [],
            petRepository: petRepository,
            healthRecordRepository: healthRecordRepository,
            reminderRepository: reminderRepository,
            notificationScheduler: notificationScheduler
        )
    }

    private static func makePreview(petRepository: (any PetRepository)? = nil) -> AppStore {
        let petID = UUID(uuidString: "3D2B3950-2272-49EF-A98C-5BEDFF9A553B")!
        let secondPetID = UUID(uuidString: "783181A1-1B7C-465F-A58D-2427A60CA22C")!
        let calendar = Calendar.current
        let now = Date()

        return AppStore(
            selectedPetID: petID,
            pets: [
                Pet(id: petID, name: "团子", species: .cat, breed: "英短", avatarSymbol: "cat.fill"),
                Pet(id: secondPetID, name: "可乐", species: .dog, breed: "柯基", avatarSymbol: "dog.fill")
            ],
            reminders: [
                ReminderItem(id: UUID(), petID: petID, title: "体内驱虫", kind: .internalDeworming, dueAt: calendar.date(byAdding: .day, value: -2, to: now)!),
                ReminderItem(id: UUID(), petID: petID, title: "年度疫苗", kind: .vaccine, dueAt: calendar.date(byAdding: .day, value: 6, to: now)!, scheduleType: .calendarYears, intervalValue: 1),
                ReminderItem(id: UUID(), petID: petID, title: "洗澡护理", kind: .bathGrooming, dueAt: calendar.date(byAdding: .day, value: 18, to: now)!, scheduleType: .intervalDays, intervalValue: 30)
            ],
            records: [
                HealthRecord(id: UUID(), petID: petID, kind: .medicalVisit, title: "年度体检", occurredAt: calendar.date(byAdding: .day, value: -12, to: now)!, providerName: "安宁动物医院", costCents: 36800),
                HealthRecord(id: UUID(), petID: petID, kind: .bathGrooming, title: "洗澡护理", occurredAt: calendar.date(byAdding: .day, value: -30, to: now)!, providerName: "毛球宠物", costCents: 12800),
                HealthRecord(id: UUID(), petID: petID, kind: .vaccine, title: "猫三联", occurredAt: calendar.date(byAdding: .month, value: -10, to: now)!, providerName: "安宁动物医院", costCents: 24000)
            ],
            hospitals: [
                HospitalSummary(id: "preview-animal-hospital-1", name: "安宁动物医院", address: "长宁区示例路 128 号", latitude: 31.2184, longitude: 121.4103, distanceMeters: 860, phoneNumber: "021-12345678", isFavorite: true),
                HospitalSummary(id: "preview-animal-hospital-2", name: "贝康宠物医院", address: "静安区示例街 66 号", latitude: 31.2312, longitude: 121.4431, distanceMeters: 1800, isFavorite: false)
            ],
            petRepository: petRepository
        )
    }
}
