import CloudKit
import SwiftData
import XCTest
@testable import Zoji

final class PersistenceRepositoryTests: XCTestCase {
    func testPetRepositorySavesUpdatesAndHardDeletes() async throws {
        let container = try makeContainer()
        let repository = SwiftDataPetRepository(modelContainer: container)
        let petID = UUID()
        let original = Pet(id: petID, name: "团子", species: .cat, breed: "英国短毛猫")

        try await repository.save(original)
        var pets = try await repository.listPets()
        XCTAssertEqual(pets.count, 1)
        XCTAssertEqual(pets.first?.name, "团子")

        var updated = original
        updated.name = "团团"
        updated.weightKilograms = 4.8
        try await repository.save(updated)
        pets = try await repository.listPets()
        XCTAssertEqual(pets.first?.name, "团团")
        XCTAssertEqual(pets.first?.weightKilograms, 4.8)

        try await repository.delete(petID: petID)
        pets = try await repository.listPets()
        XCTAssertTrue(pets.isEmpty)
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PetEntity>()).isEmpty)
    }

    func testHealthRecordRepositoryPreservesImageAndPDFThenRemovesDeletedAttachment() async throws {
        let container = try makeContainer()
        let repository = SwiftDataHealthRecordRepository(modelContainer: container)
        let petID = UUID()
        let imageAttachment = HealthRecordAttachment(
            id: UUID(),
            kind: .image,
            data: Data([1, 2, 3]),
            originalName: "病例.jpg"
        )
        let pdfAttachment = HealthRecordAttachment(
            id: UUID(),
            kind: .pdf,
            data: Data([4, 5, 6]),
            originalName: "检查报告.pdf"
        )
        var record = HealthRecord(
            id: UUID(),
            petID: petID,
            kind: .medicalVisit,
            title: "腹泻复诊",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            providerName: "示例动物医院",
            costCents: 12_345,
            currencyCode: "USD",
            timeZoneIdentifier: "America/Los_Angeles",
            notes: "精神状态恢复。",
            attachments: [imageAttachment, pdfAttachment]
        )

        try await repository.save(record)
        var records = try await repository.listRecords(petID: petID)
        XCTAssertEqual(records.first?.attachments.count, 2)
        XCTAssertEqual(records.first?.attachments.map(\.kind), [.image, .pdf])
        XCTAssertEqual(records.first?.attachments.last?.originalName, "检查报告.pdf")
        XCTAssertEqual(records.first?.attachments.map(\.data), [Data(), Data()])
        XCTAssertEqual(records.first?.costCents, 12_345)
        XCTAssertEqual(records.first?.currencyCode, "USD")
        XCTAssertEqual(records.first?.timeZoneIdentifier, "America/Los_Angeles")

        let completeRecord = try await repository.record(id: record.id)
        XCTAssertEqual(completeRecord?.attachments.map(\.data), [Data([1, 2, 3]), Data([4, 5, 6])])

        let completeRecords = try await repository.listRecords(
            petID: petID,
            includingAttachmentData: true
        )
        XCTAssertEqual(completeRecords.first?.attachments.map(\.data), [Data([1, 2, 3]), Data([4, 5, 6])])

        record.attachments = [pdfAttachment]
        try await repository.save(record)
        records = try await repository.listRecords(petID: petID)
        XCTAssertEqual(records.first?.attachments.map(\.id), [pdfAttachment.id])
        var context = ModelContext(container)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<HealthRecordAttachmentEntity>()).map(\.id),
            [pdfAttachment.id]
        )

        try await repository.delete(recordID: record.id)
        records = try await repository.listRecords(petID: petID)
        XCTAssertTrue(records.isEmpty)
        context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<HealthRecordEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<HealthRecordAttachmentEntity>()).isEmpty)
    }

    func testReminderRepositoryPreservesCompletionStateAndHardDeletes() async throws {
        let container = try makeContainer()
        let repository = SwiftDataReminderRepository(modelContainer: container)
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let reminder = ReminderItem(
            id: UUID(),
            petID: UUID(),
            title: "洗澡护理",
            kind: .bathGrooming,
            dueAt: Date(timeIntervalSince1970: 1_702_592_000),
            scheduleType: .intervalDays,
            intervalValue: 30,
            advanceDays: [3, 1, 0],
            isEnabled: true,
            lastCompletedAt: completedAt
        )

        try await repository.save(reminder)
        var reminders = try await repository.listReminders(petID: reminder.petID)
        let stored = try XCTUnwrap(reminders.first)
        XCTAssertEqual(stored.intervalValue, 30)
        XCTAssertEqual(stored.advanceDays, [3, 1, 0])
        XCTAssertEqual(stored.lastCompletedAt, completedAt)

        try await repository.delete(reminderID: reminder.id)
        reminders = try await repository.listReminders(petID: reminder.petID)
        XCTAssertTrue(reminders.isEmpty)
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReminderRuleEntity>()).isEmpty)
    }

    func testHealthRecordRepositoryPurgesLegacySoftDeletesAndOrphanedAttachments() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recordID = UUID()
        let legacyRecord = HealthRecordEntity(
            id: recordID,
            petID: UUID(),
            kind: .custom,
            title: "Legacy deleted record",
            occurredAt: Date()
        )
        legacyRecord.deletedAt = Date()
        let orphanedAttachment = HealthRecordAttachmentEntity(
            id: UUID(),
            recordID: recordID,
            kind: .image,
            data: Data([1, 2, 3]),
            originalName: "legacy.jpg"
        )
        context.insert(legacyRecord)
        context.insert(orphanedAttachment)
        try context.save()

        let repository = SwiftDataHealthRecordRepository(modelContainer: container)
        try await repository.purgeLegacySoftDeletedEntities()

        let verificationContext = ModelContext(container)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<HealthRecordEntity>()).isEmpty)
        XCTAssertTrue(
            try verificationContext.fetch(FetchDescriptor<HealthRecordAttachmentEntity>()).isEmpty
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PetEntity.self,
            HealthRecordEntity.self,
            HealthRecordAttachmentEntity.self,
            ReminderRuleEntity.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

final class FamilyPetSharePayloadTests: XCTestCase {
    func testAttachmentHydrationSelectsOnlyTheEditedHealthRecordsAssets() {
        let zoneID = CKRecordZone.ID(zoneName: "test-zone", ownerName: "owner")
        let targetHealthID = UUID()
        let otherHealthID = UUID()
        let targetAttachmentID = CKRecord.ID(recordName: "target-attachment", zoneID: zoneID)
        let otherAttachmentID = CKRecord.ID(recordName: "other-attachment", zoneID: zoneID)
        let bodyID = CKRecord.ID(recordName: "health-body", zoneID: zoneID)

        let targetAttachment = CKRecord(
            recordType: "ZojiFamilyAttachment",
            recordID: targetAttachmentID
        )
        targetAttachment["healthRecordID"] = targetHealthID.uuidString as CKRecordValue
        let otherAttachment = CKRecord(
            recordType: "ZojiFamilyAttachment",
            recordID: otherAttachmentID
        )
        otherAttachment["healthRecordID"] = otherHealthID.uuidString as CKRecordValue
        let body = CKRecord(recordType: "ZojiFamilyHealthRecord", recordID: bodyID)

        let selected = FamilySharingService.attachmentRecordIDs(
            for: targetHealthID,
            in: [
                targetAttachmentID: targetAttachment,
                otherAttachmentID: otherAttachment,
                bodyID: body,
            ]
        )

        XCTAssertEqual(selected, [targetAttachmentID])
    }

    func testPayloadContainsOnlyTheSelectedPetsDataAndAttachments() throws {
        let selectedPet = Pet(id: UUID(), name: "团子", species: .cat)
        let otherPet = Pet(id: UUID(), name: "毛毛", species: .dog)
        let selectedRecord = HealthRecord(
            id: UUID(),
            petID: selectedPet.id,
            kind: .medicalVisit,
            title: "复诊",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            attachments: [
                HealthRecordAttachment(
                    kind: .pdf,
                    data: Data([1, 2, 3]),
                    originalName: "检查报告.pdf"
                )
            ]
        )
        let otherRecord = HealthRecord(
            id: UUID(),
            petID: otherPet.id,
            kind: .vaccine,
            title: "其他宠物的疫苗",
            occurredAt: Date()
        )
        let selectedReminder = ReminderItem(
            id: UUID(),
            petID: selectedPet.id,
            title: "下次复诊",
            kind: .medicalVisit,
            dueAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let otherReminder = ReminderItem(
            id: UUID(),
            petID: otherPet.id,
            title: "其他宠物的驱虫",
            kind: .internalDeworming,
            dueAt: Date()
        )

        let payload = FamilyPetSharePayload(
            pet: selectedPet,
            records: [selectedRecord, otherRecord],
            reminders: [selectedReminder, otherReminder]
        )

        try payload.validate()
        XCTAssertEqual(payload.pet.id, selectedPet.id)
        XCTAssertEqual(payload.records.map(\.id), [selectedRecord.id])
        XCTAssertEqual(payload.records.first?.attachments.first?.data, Data([1, 2, 3]))
        XCTAssertEqual(payload.reminders.map(\.id), [selectedReminder.id])
    }

    func testPayloadRejectsCrossPetRelationshipsAfterDecodingOrMutation() {
        let pet = Pet(id: UUID(), name: "团子", species: .cat)
        var payload = FamilyPetSharePayload(pet: pet, records: [], reminders: [])
        payload.records = [
            HealthRecord(
                id: UUID(),
                petID: UUID(),
                kind: .custom,
                title: "不属于团子的记录",
                occurredAt: Date()
            )
        ]

        XCTAssertThrowsError(try payload.validate()) { error in
            XCTAssertEqual(error as? FamilySharingError, .invalidPayload)
        }
    }

    func testPendingFamilyChangesKeepLatestEditAndSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZojiFamilyQueueTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let petID = UUID()
        let location = FamilyShareLocation(
            zoneName: "ZojiPet_\(petID.uuidString)",
            zoneOwnerName: "owner",
            databaseScope: .shared
        )
        let first = Pet(id: petID, name: "布布", species: .dog)
        var latest = first
        latest.name = "布丁"

        let firstStore = FamilySharingLocalStore(directory: directory)
        try await firstStore.enqueue(.save(first, at: location))
        try await firstStore.enqueue(.save(latest, at: location))

        let firstCount = try await firstStore.pendingCount()
        let firstPendingName = try await firstStore.nextPendingChange()?.pet?.name
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(firstPendingName, "布丁")

        let relaunchedStore = FamilySharingLocalStore(directory: directory)
        let relaunchedCount = try await relaunchedStore.pendingCount()
        let relaunchedPendingName = try await relaunchedStore.nextPendingChange()?.pet?.name
        XCTAssertEqual(relaunchedCount, 1)
        XCTAssertEqual(relaunchedPendingName, "布丁")
    }

    func testSharedPetCacheSurvivesRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZojiFamilyCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pet = Pet(id: UUID(), name: "布布", species: .dog)
        let sharedPet = FamilySharedPet(
            location: FamilyShareLocation(
                zoneName: "ZojiPet_\(pet.id.uuidString)",
                zoneOwnerName: "owner",
                databaseScope: .shared
            ),
            ownerName: "家人",
            role: .editor,
            payload: FamilyPetSharePayload(pet: pet, records: [], reminders: [])
        )

        let firstStore = FamilySharingLocalStore(directory: directory)
        try await firstStore.upsertCachedPet(sharedPet)

        let relaunchedStore = FamilySharingLocalStore(directory: directory)
        let cached = try await relaunchedStore.cachedSharedPets()
        XCTAssertEqual(cached.map(\.pet.name), ["布布"])
        XCTAssertEqual(cached.first?.role, .editor)
    }

    @MainActor
    func testFamilyStoreRestoresSharedPetBeforeCloudRefresh() throws {
        let defaultsName = "ZojiFamilySelectionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let pet = Pet(id: UUID(), name: "布布", species: .dog)
        let sharedPet = FamilySharedPet(
            location: FamilyShareLocation(
                zoneName: "ZojiPet_\(pet.id.uuidString)",
                zoneOwnerName: "owner",
                databaseScope: .shared
            ),
            ownerName: "家人",
            role: .editor,
            payload: FamilyPetSharePayload(pet: pet, records: [], reminders: [])
        )

        let store = FamilySharingStore(
            restoredSharedPets: [sharedPet],
            selectionDefaults: defaults
        )

        XCTAssertEqual(store.selectedSharedPet?.pet.name, "布布")
        store.resolveLaunchSelection(hasPrivatePets: false)
        XCTAssertEqual(defaults.string(forKey: "familySharing.selectedSharedPetID"), sharedPet.id)
    }

    @MainActor
    func testHospitalViewModelDefersFavoriteLoadingAndActivatesOnlyOnce() throws {
        let defaultsName = "ZojiHospitalFavoriteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let favorite = HospitalSummary(
            id: "hospital-1",
            name: "示例宠物医院",
            address: "上海市",
            latitude: 31.23,
            longitude: 121.47,
            distanceMeters: 800,
            isFavorite: true
        )
        let favoriteStore = HospitalFavoriteStore(
            defaults: defaults,
            ubiquitousStore: nil
        )
        favoriteStore.save([favorite])
        let storedSnapshot = defaults.data(forKey: "zoji.favorite-hospitals.v3")

        let model = HospitalsViewModel(favoriteStore: favoriteStore)
        XCTAssertTrue(model.favorites.isEmpty)

        model.activate()
        XCTAssertEqual(model.favorites.map(\.id), [favorite.id])
        XCTAssertEqual(defaults.data(forKey: "zoji.favorite-hospitals.v3"), storedSnapshot)

        model.activate()
        XCTAssertEqual(model.favorites.map(\.id), [favorite.id])
        XCTAssertEqual(defaults.data(forKey: "zoji.favorite-hospitals.v3"), storedSnapshot)
    }

    func testRevokedOwnedShareRemovesStaleLocationAndQueuedWrites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZojiFamilyOwnerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pet = Pet(id: UUID(), name: "布布", species: .dog)
        let location = FamilyShareLocation(
            zoneName: "ZojiPet_\(pet.id.uuidString)",
            zoneOwnerName: "owner",
            databaseScope: .ownerPrivate
        )
        let store = FamilySharingLocalStore(directory: directory)
        try await store.registerOwned([pet.id: location])
        try await store.enqueue(.save(pet, at: location))

        try await store.reconcileOwned([:], checkedPetIDs: [pet.id])

        let remainingLocation = try await store.ownedLocation(for: pet.id)
        let remainingChanges = try await store.pendingCount()
        XCTAssertNil(remainingLocation)
        XCTAssertEqual(remainingChanges, 0)
    }

    func testSharedShareReferenceUsesReceivedRootZoneOwner() {
        let staleReference = CKRecord.ID(
            recordName: "share_pet",
            zoneID: CKRecordZone.ID(
                zoneName: "ZojiPet_pet",
                ownerName: "__defaultOwner__"
            )
        )
        let discoveredSharedZone = CKRecordZone.ID(
            zoneName: "ZojiPet_pet",
            ownerName: "_realCloudKitOwner"
        )

        let resolved = FamilySharingService.resolvedShareRecordID(
            referencedShareID: staleReference,
            sharedZoneID: discoveredSharedZone,
            databaseScope: .shared
        )

        XCTAssertEqual(resolved.recordName, staleReference.recordName)
        XCTAssertEqual(resolved.zoneID, discoveredSharedZone)
    }
}
