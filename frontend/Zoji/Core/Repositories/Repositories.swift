import Foundation
import SwiftData

protocol PetRepository: Sendable {
    func listPets() async throws -> [Pet]
    func save(_ pet: Pet) async throws
    func delete(petID: UUID) async throws
}

protocol HealthRecordRepository: Sendable {
    func listRecords(petID: UUID) async throws -> [HealthRecord]
    func save(_ record: HealthRecord) async throws
    func delete(recordID: UUID) async throws
    func deleteAll(petID: UUID) async throws
}

protocol ReminderRepository: Sendable {
    func listReminders(petID: UUID) async throws -> [ReminderItem]
    func save(_ reminder: ReminderItem) async throws
    func delete(reminderID: UUID) async throws
    func deleteAll(petID: UUID) async throws
}

enum PrivateDataScope {
    // Kept only for compatibility with the pre-iCloud local schema. CloudKit's
    // private database already isolates every person's records by Apple Account.
    static let ownerID = UUID(uuidString: "65CA5668-CED8-4D35-A443-327E3E1E6785")!
}

/// T01 uses preview data. T04 will add SwiftData-backed repositories and a pending-change queue.
struct PreviewPetRepository: PetRepository {
    let pets: [Pet]

    func listPets() async throws -> [Pet] { pets }
    func save(_ pet: Pet) async throws { }
    func delete(petID: UUID) async throws { }
}

/// Local-first storage mirrored automatically into the user's private CloudKit database.
@ModelActor
actor SwiftDataPetRepository: PetRepository {
    func listPets() async throws -> [Pet] {
        let descriptor = FetchDescriptor<PetEntity>(
            predicate: #Predicate { entity in
                entity.deletedAt == nil
            },
            sortBy: [SortDescriptor(\PetEntity.createdAt)]
        )

        return try modelContext.fetch(descriptor).map { entity in
            let species = PetSpecies(rawValue: entity.speciesRawValue) ?? .other
            return Pet(
                id: entity.id,
                name: entity.name,
                species: species,
                breed: entity.breed,
                avatarSymbol: species.avatarSymbol,
                avatarData: entity.avatarData,
                avatarPresetID: entity.avatarPresetID,
                sex: entity.sexRawValue.flatMap { PetSex(rawValue: $0) },
                birthday: entity.birthday,
                weightKilograms: entity.weightKilograms,
                weightEntries: decodeWeightEntries(entity.weightHistoryData)
            )
        }
    }

    func save(_ pet: Pet) async throws {
        let petID = pet.id
        let descriptor = FetchDescriptor<PetEntity>(
            predicate: #Predicate { $0.id == petID }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            entity.name = pet.name
            entity.speciesRawValue = pet.species.rawValue
            entity.breed = pet.breed
            entity.avatarData = pet.avatarData
            entity.avatarPresetID = pet.avatarPresetID
            entity.sexRawValue = pet.sex?.rawValue
            entity.birthday = pet.birthday
            entity.weightKilograms = pet.weightKilograms
            entity.weightHistoryData = encodeWeightEntries(pet.weightEntries)
            entity.updatedAt = Date()
            entity.syncStateRawValue = "pending"
        } else {
            let entity = PetEntity(
                id: pet.id,
                ownerID: PrivateDataScope.ownerID,
                name: pet.name,
                species: pet.species
            )
            entity.breed = pet.breed
            entity.avatarData = pet.avatarData
            entity.avatarPresetID = pet.avatarPresetID
            entity.sexRawValue = pet.sex?.rawValue
            entity.birthday = pet.birthday
            entity.weightKilograms = pet.weightKilograms
            entity.weightHistoryData = encodeWeightEntries(pet.weightEntries)
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    func delete(petID: UUID) async throws {
        let descriptor = FetchDescriptor<PetEntity>(
            predicate: #Predicate { $0.id == petID }
        )
        guard let entity = try modelContext.fetch(descriptor).first else { return }

        entity.deletedAt = Date()
        entity.updatedAt = Date()
        entity.syncStateRawValue = "pending"
        try modelContext.save()
    }

    private func decodeWeightEntries(_ data: Data?) -> [WeightEntry]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([WeightEntry].self, from: data)
    }

    private func encodeWeightEntries(_ entries: [WeightEntry]?) -> Data? {
        guard let entries else { return nil }
        return try? JSONEncoder().encode(entries)
    }
}

@ModelActor
actor SwiftDataHealthRecordRepository: HealthRecordRepository {
    func listRecords(petID: UUID) async throws -> [HealthRecord] {
        let descriptor = FetchDescriptor<HealthRecordEntity>(
            predicate: #Predicate { entity in
                entity.petID == petID && entity.deletedAt == nil
            },
            sortBy: [SortDescriptor(\HealthRecordEntity.occurredAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { entity in
            let attachments = try attachments(for: entity)
            return HealthRecord(
                id: entity.id,
                petID: entity.petID,
                kind: RecordKind(rawValue: entity.kindRawValue) ?? .custom,
                title: entity.title,
                occurredAt: entity.occurredAt,
                providerName: entity.providerName,
                costCents: entity.costCents,
                currencyCode: entity.currencyCode,
                notes: entity.notes,
                attachments: attachments
            )
        }
    }

    func save(_ record: HealthRecord) async throws {
        let recordID = record.id
        let descriptor = FetchDescriptor<HealthRecordEntity>(
            predicate: #Predicate { $0.id == recordID }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            entity.kindRawValue = record.kind.rawValue
            entity.title = record.title
            entity.occurredAt = record.occurredAt
            entity.providerName = record.providerName
            entity.costCents = record.costCents
            entity.currencyCode = record.currencyCode
            entity.notes = record.notes
            entity.caseImageData = nil
            entity.deletedAt = nil
            entity.updatedAt = Date()
            entity.syncStateRawValue = "pending"
        } else {
            let entity = HealthRecordEntity(
                id: record.id,
                petID: record.petID,
                kind: record.kind,
                title: record.title,
                occurredAt: record.occurredAt
            )
            entity.providerName = record.providerName
            entity.costCents = record.costCents
            entity.currencyCode = record.currencyCode
            entity.notes = record.notes
            modelContext.insert(entity)
        }

        try saveAttachments(record.attachments, recordID: record.id)

        try modelContext.save()
    }

    func delete(recordID: UUID) async throws {
        let descriptor = FetchDescriptor<HealthRecordEntity>(
            predicate: #Predicate { $0.id == recordID }
        )
        guard let entity = try modelContext.fetch(descriptor).first else { return }

        entity.deletedAt = Date()
        entity.updatedAt = Date()
        entity.syncStateRawValue = "pending"
        try softDeleteAttachments(recordID: recordID, at: entity.updatedAt)
        try modelContext.save()
    }

    func deleteAll(petID: UUID) async throws {
        let descriptor = FetchDescriptor<HealthRecordEntity>(
            predicate: #Predicate { entity in
                entity.petID == petID && entity.deletedAt == nil
            }
        )
        let records = try modelContext.fetch(descriptor)
        guard !records.isEmpty else { return }

        let now = Date()
        for entity in records {
            entity.deletedAt = now
            entity.updatedAt = now
            entity.syncStateRawValue = "pending"
            try softDeleteAttachments(recordID: entity.id, at: now)
        }
        try modelContext.save()
    }

    private func attachments(for record: HealthRecordEntity) throws -> [HealthRecordAttachment] {
        let recordID = record.id
        let descriptor = FetchDescriptor<HealthRecordAttachmentEntity>(
            predicate: #Predicate { entity in
                entity.recordID == recordID && entity.deletedAt == nil
            },
            sortBy: [SortDescriptor(\HealthRecordAttachmentEntity.createdAt)]
        )
        let storedAttachments = try modelContext.fetch(descriptor).map { entity in
            HealthRecordAttachment(
                id: entity.id,
                kind: entity.kindRawValue.flatMap(HealthRecordAttachmentKind.init(rawValue:)) ?? .image,
                data: entity.imageData,
                originalName: entity.originalName,
                createdAt: entity.createdAt
            )
        }

        if storedAttachments.isEmpty, let legacyImageData = record.caseImageData {
            return [HealthRecordAttachment(id: record.id, data: legacyImageData, createdAt: record.createdAt)]
        }
        return storedAttachments
    }

    private func saveAttachments(_ attachments: [HealthRecordAttachment], recordID: UUID) throws {
        let descriptor = FetchDescriptor<HealthRecordAttachmentEntity>(
            predicate: #Predicate { $0.recordID == recordID }
        )
        let existingAttachments = try modelContext.fetch(descriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: existingAttachments.map { ($0.id, $0) })
        let retainedIDs = Set(attachments.map(\.id))
        let now = Date()

        for attachment in attachments {
            if let entity = existingByID[attachment.id] {
                entity.imageData = attachment.data
                entity.kindRawValue = attachment.kind.rawValue
                entity.originalName = attachment.originalName
                entity.deletedAt = nil
                entity.updatedAt = now
                entity.syncStateRawValue = "pending"
            } else {
                modelContext.insert(HealthRecordAttachmentEntity(
                    id: attachment.id,
                    recordID: recordID,
                    kind: attachment.kind,
                    data: attachment.data,
                    originalName: attachment.originalName,
                    createdAt: attachment.createdAt
                ))
            }
        }

        for entity in existingAttachments where !retainedIDs.contains(entity.id) && entity.deletedAt == nil {
            entity.deletedAt = now
            entity.updatedAt = now
            entity.syncStateRawValue = "pending"
        }
    }

    private func softDeleteAttachments(recordID: UUID, at date: Date) throws {
        let descriptor = FetchDescriptor<HealthRecordAttachmentEntity>(
            predicate: #Predicate { entity in
                entity.recordID == recordID && entity.deletedAt == nil
            }
        )
        for entity in try modelContext.fetch(descriptor) {
            entity.deletedAt = date
            entity.updatedAt = date
            entity.syncStateRawValue = "pending"
        }
    }
}

@ModelActor
actor SwiftDataReminderRepository: ReminderRepository {
    func listReminders(petID: UUID) async throws -> [ReminderItem] {
        let descriptor = FetchDescriptor<ReminderRuleEntity>(
            predicate: #Predicate { entity in
                entity.petID == petID && entity.deletedAt == nil
            },
            sortBy: [SortDescriptor(\ReminderRuleEntity.dueAt)]
        )

        return try modelContext.fetch(descriptor).map { entity in
            let kind = RecordKind(rawValue: entity.kindRawValue) ?? .custom
            return ReminderItem(
                id: entity.id,
                petID: entity.petID,
                sourceRecordID: entity.sourceRecordID,
                title: entity.title?.isEmpty == false ? entity.title! : kind.displayName,
                kind: kind,
                dueAt: entity.dueAt,
                scheduleType: ScheduleType(rawValue: entity.scheduleTypeRawValue) ?? .oneOff,
                intervalValue: entity.intervalValue,
                advanceDays: entity.advanceDays,
                isEnabled: entity.enabled,
                lastCompletedAt: entity.lastCompletedAt
            )
        }
    }

    func save(_ reminder: ReminderItem) async throws {
        let reminderID = reminder.id
        let descriptor = FetchDescriptor<ReminderRuleEntity>(
            predicate: #Predicate { $0.id == reminderID }
        )

        let entity: ReminderRuleEntity
        if let storedEntity = try modelContext.fetch(descriptor).first {
            entity = storedEntity
        } else {
            entity = ReminderRuleEntity(
                id: reminder.id,
                petID: reminder.petID,
                kind: reminder.kind,
                scheduleType: reminder.scheduleType,
                dueAt: reminder.dueAt
            )
            modelContext.insert(entity)
        }

        entity.petID = reminder.petID
        entity.sourceRecordID = reminder.sourceRecordID
        entity.title = reminder.title
        entity.kindRawValue = reminder.kind.rawValue
        entity.scheduleTypeRawValue = reminder.scheduleType.rawValue
        entity.intervalValue = reminder.intervalValue
        entity.dueAt = reminder.dueAt
        entity.advanceDays = reminder.advanceDays
        entity.enabled = reminder.isEnabled
        entity.lastCompletedAt = reminder.lastCompletedAt
        entity.deletedAt = nil
        entity.updatedAt = Date()
        entity.syncStateRawValue = "pending"
        try modelContext.save()
    }

    func delete(reminderID: UUID) async throws {
        let descriptor = FetchDescriptor<ReminderRuleEntity>(
            predicate: #Predicate { $0.id == reminderID }
        )
        guard let entity = try modelContext.fetch(descriptor).first else { return }

        entity.deletedAt = Date()
        entity.updatedAt = Date()
        entity.syncStateRawValue = "pending"
        try modelContext.save()
    }

    func deleteAll(petID: UUID) async throws {
        let descriptor = FetchDescriptor<ReminderRuleEntity>(
            predicate: #Predicate { entity in
                entity.petID == petID && entity.deletedAt == nil
            }
        )
        let entities = try modelContext.fetch(descriptor)
        guard !entities.isEmpty else { return }

        let now = Date()
        for entity in entities {
            entity.deletedAt = now
            entity.updatedAt = now
            entity.syncStateRawValue = "pending"
        }
        try modelContext.save()
    }
}
