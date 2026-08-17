import Foundation
import SwiftData

@Model
final class PetEntity {
    var id: UUID = UUID()
    var ownerID: UUID = PrivateDataScope.ownerID
    var name: String = ""
    var speciesRawValue: String = PetSpecies.other.rawValue
    var breed: String?
    @Attribute(.externalStorage) var avatarData: Data?
    var avatarPresetID: String?
    var sexRawValue: String?
    var birthday: Date?
    var weightKilograms: Double?
    @Attribute(.externalStorage) var weightHistoryData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var revision: Int = 0
    var syncStateRawValue: String = "clean"

    init(id: UUID, ownerID: UUID, name: String, species: PetSpecies) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.speciesRawValue = species.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.revision = 0
        self.syncStateRawValue = "pending"
    }
}

@Model
final class HealthRecordEntity {
    var id: UUID = UUID()
    var petID: UUID = UUID()
    var kindRawValue: String = RecordKind.custom.rawValue
    var title: String = ""
    var occurredAt: Date = Date()
    var providerName: String?
    var costCents: Int?
    var currencyCode: String?
    var timeZoneIdentifier: String?
    var notes: String?
    @Attribute(.externalStorage) var caseImageData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var revision: Int = 0
    var syncStateRawValue: String = "clean"

    init(id: UUID, petID: UUID, kind: RecordKind, title: String, occurredAt: Date) {
        self.id = id
        self.petID = petID
        self.kindRawValue = kind.rawValue
        self.title = title
        self.occurredAt = occurredAt
        self.createdAt = Date()
        self.updatedAt = Date()
        self.revision = 0
        self.syncStateRawValue = "pending"
    }
}

@Model
final class HealthRecordAttachmentEntity {
    var id: UUID = UUID()
    var recordID: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var kindRawValue: String?
    var originalName: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var syncStateRawValue: String = "clean"

    init(
        id: UUID,
        recordID: UUID,
        kind: HealthRecordAttachmentKind,
        data: Data,
        originalName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordID = recordID
        self.imageData = data
        self.kindRawValue = kind.rawValue
        self.originalName = originalName
        self.createdAt = createdAt
        self.updatedAt = Date()
        self.syncStateRawValue = "pending"
    }
}

@Model
final class ReminderRuleEntity {
    var id: UUID = UUID()
    var petID: UUID = UUID()
    var sourceRecordID: UUID?
    var title: String?
    var kindRawValue: String = RecordKind.custom.rawValue
    var scheduleTypeRawValue: String = ScheduleType.oneOff.rawValue
    var intervalValue: Int?
    var dueAt: Date = Date()
    var advanceDays: [Int] = []
    var enabled: Bool = true
    var lastCompletedAt: Date?
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var revision: Int = 0
    var syncStateRawValue: String = "clean"

    init(id: UUID, petID: UUID, kind: RecordKind, scheduleType: ScheduleType, dueAt: Date) {
        self.id = id
        self.petID = petID
        self.kindRawValue = kind.rawValue
        self.scheduleTypeRawValue = scheduleType.rawValue
        self.dueAt = dueAt
        self.advanceDays = []
        self.enabled = true
        self.updatedAt = Date()
        self.revision = 0
        self.syncStateRawValue = "pending"
    }
}
