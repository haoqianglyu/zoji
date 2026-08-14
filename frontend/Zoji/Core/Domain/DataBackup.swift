import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ZojiBackupArchive: Codable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumArchiveBytes = 300_000_000

    var schemaVersion: Int
    var exportedAt: Date
    var selectedPetID: UUID?
    var pets: [Pet]
    var records: [HealthRecord]
    var reminders: [ReminderItem]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        selectedPetID: UUID?,
        pets: [Pet],
        records: [HealthRecord],
        reminders: [ReminderItem]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.selectedPetID = selectedPetID
        self.pets = pets
        self.records = records
        self.reminders = reminders
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ZojiBackupError.unsupportedVersion
        }
        guard pets.count <= 100,
              records.count <= 50_000,
              reminders.count <= 10_000 else {
            throw ZojiBackupError.tooManyItems
        }

        let petIDs = Set(pets.map(\.id))
        guard petIDs.count == pets.count else {
            throw ZojiBackupError.duplicateIdentifiers
        }
        guard records.allSatisfy({ petIDs.contains($0.petID) }),
              reminders.allSatisfy({ petIDs.contains($0.petID) }) else {
            throw ZojiBackupError.brokenRelationships
        }
        guard Set(records.map(\.id)).count == records.count,
              Set(reminders.map(\.id)).count == reminders.count else {
            throw ZojiBackupError.duplicateIdentifiers
        }

        var binaryDataBytes = pets.reduce(into: 0) { total, pet in
            total += pet.avatarData?.count ?? 0
        }
        for record in records {
            guard record.attachments.count <= HealthRecordAttachmentPolicy.maximumCount else {
                throw ZojiBackupError.tooManyAttachments
            }
            var recordAttachmentBytes = 0
            for attachment in record.attachments {
                let maximumBytes = HealthRecordAttachmentPolicy.maximumBytes(for: attachment.kind)
                guard attachment.data.count <= maximumBytes else {
                    throw ZojiBackupError.attachmentTooLarge
                }
                recordAttachmentBytes += attachment.data.count
                binaryDataBytes += attachment.data.count
            }
            guard recordAttachmentBytes <= HealthRecordAttachmentPolicy.maximumTotalBytes else {
                throw ZojiBackupError.attachmentsTotalTooLarge
            }
        }
        // JSON base64 encoding adds roughly one third to binary payloads. Keep
        // the exported file comfortably below the 300 MB import ceiling.
        guard binaryDataBytes <= 200_000_000 else {
            throw ZojiBackupError.fileTooLarge
        }
    }
}

struct ZojiBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let archive: ZojiBackupArchive

    init(archive: ZojiBackupArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw ZojiBackupError.invalidFile
        }
        guard data.count <= ZojiBackupArchive.maximumArchiveBytes else {
            throw ZojiBackupError.fileTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        archive = try decoder.decode(ZojiBackupArchive.self, from: data)
        try archive.validate()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encode(archive))
    }

    static func encode(_ archive: ZojiBackupArchive) throws -> Data {
        try archive.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= ZojiBackupArchive.maximumArchiveBytes else {
            throw ZojiBackupError.fileTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> ZojiBackupArchive {
        guard data.count <= ZojiBackupArchive.maximumArchiveBytes else {
            throw ZojiBackupError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ZojiBackupArchive.self, from: data)
        try archive.validate()
        return archive
    }
}

enum ZojiBackupError: LocalizedError {
    case invalidFile
    case fileTooLarge
    case unsupportedVersion
    case tooManyItems
    case duplicateIdentifiers
    case brokenRelationships
    case tooManyAttachments
    case attachmentTooLarge
    case attachmentsTotalTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFile: L10n.string("无法读取这个备份文件。")
        case .fileTooLarge: L10n.string("备份文件过大，最大支持 300 MB。")
        case .unsupportedVersion: L10n.string("这个备份由不兼容的爪记版本创建。")
        case .tooManyItems: L10n.string("备份中的数据条目数量异常。")
        case .duplicateIdentifiers: L10n.string("备份中存在重复数据，无法安全导入。")
        case .brokenRelationships: L10n.string("备份中的记录没有对应宠物，无法安全导入。")
        case .tooManyAttachments: L10n.string("备份中的单条记录超过 9 个附件。")
        case .attachmentTooLarge: L10n.string("备份包含过大的图片或 PDF。")
        case .attachmentsTotalTooLarge: L10n.string("备份中的单条记录附件总计超过 75 MB。")
        }
    }
}
