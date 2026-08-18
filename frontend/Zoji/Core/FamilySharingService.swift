import CloudKit
import CoreTransferable
import CryptoKit
import Foundation
import Network
import Observation
import UserNotifications

@MainActor
@Observable
final class FamilyShareAcceptanceState {
    static let shared = FamilyShareAcceptanceState()

    enum Phase: Equatable {
        case idle
        case accepting
        case loadingSharedPet
        case failed(String)
    }

    var phase: Phase = .idle
    var targetZoneName: String?
    var targetZoneOwnerName: String?

    var isLoading: Bool {
        phase == .accepting || phase == .loadingSharedPet
    }

    var title: String {
        phase == .accepting
            ? L10n.string("正在接受家庭邀请")
            : L10n.string("正在加入家庭共享")
    }

    func begin(metadata: CKShare.Metadata) {
        targetZoneName = metadata.share.recordID.zoneID.zoneName
        targetZoneOwnerName = metadata.share.recordID.zoneID.ownerName
        phase = .accepting
    }

    func beginLoading() {
        phase = .loadingSharedPet
    }

    func finish() {
        phase = .idle
        targetZoneName = nil
        targetZoneOwnerName = nil
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }
}

enum FamilyAccessRole: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case owner
    case editor
    case viewer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .owner: L10n.string("拥有者")
        case .editor: L10n.string("可编辑")
        case .viewer: L10n.string("仅查看")
        }
    }

    var detail: String {
        switch self {
        case .owner: L10n.string("管理宠物资料、记录、提醒和共享成员")
        case .editor: L10n.string("可以添加和修改资料、记录及提醒")
        case .viewer: L10n.string("可以查看档案，但不能修改或删除内容")
        }
    }

    var symbol: String {
        switch self {
        case .owner: "crown.fill"
        case .editor: "pencil.and.list.clipboard"
        case .viewer: "eye.fill"
        }
    }

    var canEdit: Bool { self != .viewer }
}

enum FamilyMemberStatus: String, Codable, Hashable, Sendable {
    case pending
    case accepted
    case removed
    case unknown

    var displayName: String {
        switch self {
        case .pending: L10n.string("等待接受")
        case .accepted: L10n.string("已加入")
        case .removed: L10n.string("已离开")
        case .unknown: L10n.string("状态未知")
        }
    }
}

struct FamilyShareMember: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let personID: String
    let displayName: String
    /// An email address or phone number supplied by CloudKit. Keep this
    /// separate from `displayName` so it is only shown on owner management UI.
    let accountIdentifier: String?
    let role: FamilyAccessRole
    let status: FamilyMemberStatus
    let isCurrentUser: Bool

    var canBeManaged: Bool { role != .owner }
}

struct FamilyShareActivity: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case joined
        case left
    }

    let id: UUID
    let petID: UUID
    let petName: String
    let memberName: String
    let kind: Kind
    let occurredAt: Date
    var isAcknowledged: Bool
    var notificationDelivered: Bool

    var message: String {
        switch kind {
        case .joined:
            String(
                localized: "\(memberName)已加入“\(petName)”的共同照护",
                locale: L10n.locale
            )
        case .left:
            String(
                localized: "\(memberName)已离开“\(petName)”的共同照护",
                locale: L10n.locale
            )
        }
    }
}

struct FamilyPetSharePayload: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var exportedAt: Date
    var pet: Pet
    var records: [HealthRecord]
    var reminders: [ReminderItem]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        pet: Pet,
        records: [HealthRecord],
        reminders: [ReminderItem]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.pet = pet
        self.records = records.filter { $0.petID == pet.id }
        self.reminders = reminders.filter { $0.petID == pet.id }
    }

    func validate() throws {
        guard (1 ... Self.currentSchemaVersion).contains(schemaVersion) else {
            throw FamilySharingError.unsupportedVersion
        }
        guard records.allSatisfy({ $0.petID == pet.id }),
              reminders.allSatisfy({ $0.petID == pet.id }) else {
            throw FamilySharingError.invalidPayload
        }
        for record in records {
            try HealthRecordAttachmentPolicy.validate(record.attachments)
        }
    }
}

enum FamilyShareDatabaseScope: String, Codable, Hashable, Sendable {
    case ownerPrivate
    case shared
}

struct FamilyShareLocation: Codable, Hashable, Sendable {
    let zoneName: String
    let zoneOwnerName: String
    let databaseScope: FamilyShareDatabaseScope

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
    }
}

struct FamilySharedPet: Codable, Identifiable, Hashable, Sendable {
    let location: FamilyShareLocation
    let ownerName: String?
    let role: FamilyAccessRole
    var payload: FamilyPetSharePayload
    var members: [FamilyShareMember]? = nil

    var id: String { "\(location.zoneOwnerName)|\(location.zoneName)" }
    var zoneName: String { location.zoneName }
    var pet: Pet { payload.pet }
    var records: [HealthRecord] { payload.records }
    var reminders: [ReminderItem] { payload.reminders }
    var canEdit: Bool { role.canEdit }
    var caregivers: [FamilyShareMember] { members ?? [] }
}

/// A UI-facing pet selection that presents private and family-shared pets
/// through one read and permission model. Persistence remains intentionally
/// separate: private writes still go through `AppStore`, while shared writes
/// continue to use `FamilySharingStore` and their CloudKit share location.
enum SelectedPet: Identifiable {
    enum ID: Hashable {
        case local(UUID)
        case shared(String)
    }

    case local(pet: Pet, records: [HealthRecord], reminders: [ReminderItem])
    case shared(FamilySharedPet)

    var id: ID {
        switch self {
        case .local(let pet, _, _): .local(pet.id)
        case .shared(let sharedPet): .shared(sharedPet.id)
        }
    }

    var pet: Pet {
        switch self {
        case .local(let pet, _, _): pet
        case .shared(let sharedPet): sharedPet.pet
        }
    }

    var records: [HealthRecord] {
        let records = switch self {
        case .local(_, let records, _): records
        case .shared(let sharedPet): sharedPet.records
        }
        return records.sorted { $0.occurredAt > $1.occurredAt }
    }

    var reminders: [ReminderItem] {
        let reminders = switch self {
        case .local(_, _, let reminders): reminders
        case .shared(let sharedPet): sharedPet.reminders
        }
        return reminders
            .filter(\.isEnabled)
            .sorted { $0.dueAt < $1.dueAt }
    }

    var canEdit: Bool {
        switch self {
        case .local: true
        case .shared(let sharedPet): sharedPet.canEdit
        }
    }

    var isShared: Bool {
        switch self {
        case .local: false
        case .shared: true
        }
    }

    var sharedPet: FamilySharedPet? {
        switch self {
        case .local: nil
        case .shared(let sharedPet): sharedPet
        }
    }

    var sharingLabel: String? {
        guard let sharedPet else { return nil }
        return String(
            localized: "家庭共享 · \(sharedPet.role.displayName)",
            locale: L10n.locale
        )
    }
}

struct FamilyReminderCompletion: Sendable {
    let reminder: ReminderItem
    let record: HealthRecord
    let nextDueAt: Date?
}

enum FamilyPendingChangeKind: String, Codable, Sendable {
    case savePet
    case deletePet
    case saveHealthRecord
    case deleteHealthRecord
    case saveReminder
    case deleteReminder
    case completeReminder
}

struct FamilyPendingChange: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let kind: FamilyPendingChangeKind
    let location: FamilyShareLocation
    let petID: UUID
    let entityID: UUID
    let pet: Pet?
    let basePet: Pet?
    let healthRecord: HealthRecord?
    let baseHealthRecord: HealthRecord?
    let reminder: ReminderItem?
    let baseReminder: ReminderItem?
    /// Version 1 stores health-record attachment bytes in queue sidecar files.
    /// `nil` identifies a legacy plist that still embeds the bytes directly.
    let attachmentStorageVersion: Int?

    init(
        id: UUID,
        createdAt: Date,
        kind: FamilyPendingChangeKind,
        location: FamilyShareLocation,
        petID: UUID,
        entityID: UUID,
        pet: Pet?,
        basePet: Pet?,
        healthRecord: HealthRecord?,
        baseHealthRecord: HealthRecord?,
        reminder: ReminderItem?,
        baseReminder: ReminderItem?,
        attachmentStorageVersion: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.location = location
        self.petID = petID
        self.entityID = entityID
        self.pet = pet
        self.basePet = basePet
        self.healthRecord = healthRecord
        self.baseHealthRecord = baseHealthRecord
        self.reminder = reminder
        self.baseReminder = baseReminder
        self.attachmentStorageVersion = attachmentStorageVersion
    }

    func replacingQueuedHealthRecords(
        healthRecord: HealthRecord?,
        baseHealthRecord: HealthRecord?,
        attachmentStorageVersion: Int?
    ) -> Self {
        Self(
            id: id,
            createdAt: createdAt,
            kind: kind,
            location: location,
            petID: petID,
            entityID: entityID,
            pet: pet,
            basePet: basePet,
            healthRecord: healthRecord,
            baseHealthRecord: baseHealthRecord,
            reminder: reminder,
            baseReminder: baseReminder,
            attachmentStorageVersion: attachmentStorageVersion
        )
    }

    var coalescingKey: String {
        let scope = "\(location.databaseScope.rawValue)|\(location.zoneOwnerName)|\(location.zoneName)"
        switch kind {
        case .savePet, .deletePet: return "\(scope)|pet|\(petID)"
        case .saveHealthRecord, .deleteHealthRecord: return "\(scope)|health|\(entityID)"
        case .saveReminder, .deleteReminder: return "\(scope)|reminder|\(entityID)"
        case .completeReminder: return "\(scope)|completion|\(healthRecord?.id.uuidString ?? id.uuidString)"
        }
    }

    static func save(_ pet: Pet, at location: FamilyShareLocation) -> Self {
        Self(id: UUID(), createdAt: Date(), kind: .savePet, location: location,
             petID: pet.id, entityID: pet.id, pet: pet, basePet: nil,
             healthRecord: nil, baseHealthRecord: nil, reminder: nil, baseReminder: nil)
    }

    static func save(_ pet: Pet, replacing basePet: Pet, at location: FamilyShareLocation) -> Self {
        Self(id: UUID(), createdAt: Date(), kind: .savePet, location: location,
             petID: pet.id, entityID: pet.id, pet: pet, basePet: basePet,
             healthRecord: nil, baseHealthRecord: nil, reminder: nil, baseReminder: nil)
    }

    static func delete(_ pet: Pet, at location: FamilyShareLocation) -> Self {
        Self(id: UUID(), createdAt: Date(), kind: .deletePet, location: location,
             petID: pet.id, entityID: pet.id, pet: pet, basePet: nil,
             healthRecord: nil, baseHealthRecord: nil, reminder: nil, baseReminder: nil)
    }

    static func save(
        _ record: HealthRecord,
        replacing baseRecord: HealthRecord? = nil,
        at location: FamilyShareLocation
    ) -> Self {
        Self(id: UUID(), createdAt: Date(), kind: .saveHealthRecord, location: location,
             petID: record.petID, entityID: record.id, pet: nil, basePet: nil,
             healthRecord: record, baseHealthRecord: baseRecord, reminder: nil, baseReminder: nil)
    }

    static func delete(_ record: HealthRecord, at location: FamilyShareLocation) -> Self {
        var tombstone = record
        tombstone.attachments = []
        return Self(id: UUID(), createdAt: Date(), kind: .deleteHealthRecord, location: location,
                    petID: record.petID, entityID: record.id, pet: nil, basePet: nil,
                    healthRecord: tombstone, baseHealthRecord: nil, reminder: nil, baseReminder: nil)
    }

    static func save(
        _ reminder: ReminderItem,
        replacing baseReminder: ReminderItem? = nil,
        at location: FamilyShareLocation
    ) -> Self {
        Self(id: UUID(), createdAt: Date(), kind: .saveReminder, location: location,
             petID: reminder.petID, entityID: reminder.id, pet: nil, basePet: nil,
             healthRecord: nil, baseHealthRecord: nil, reminder: reminder, baseReminder: baseReminder)
    }

    static func delete(_ reminder: ReminderItem, at location: FamilyShareLocation) -> Self {
        Self(id: UUID(), createdAt: Date(), kind: .deleteReminder, location: location,
             petID: reminder.petID, entityID: reminder.id, pet: nil, basePet: nil,
             healthRecord: nil, baseHealthRecord: nil, reminder: reminder, baseReminder: nil)
    }

    static func complete(
        _ reminder: ReminderItem,
        replacing baseReminder: ReminderItem,
        record: HealthRecord,
        at location: FamilyShareLocation
    ) -> Self {
        Self(id: UUID(), createdAt: Date(), kind: .completeReminder, location: location,
             petID: reminder.petID, entityID: reminder.id, pet: nil, basePet: nil,
             healthRecord: record, baseHealthRecord: nil,
             reminder: reminder, baseReminder: baseReminder)
    }
}

private struct FamilyOwnedLocationRegistration: Codable, Sendable {
    let petID: UUID
    let location: FamilyShareLocation
}

private struct FamilyMemberSnapshot: Codable, Sendable {
    let petID: UUID
    let petName: String
    let members: [FamilyShareMember]
}

actor FamilySharingLocalStore {
    static let shared = FamilySharingLocalStore()

    private var didLoad = false
    private var pendingChanges: [FamilyPendingChange] = []
    private var sharedPetCache: [String: FamilySharedPet] = [:]
    private var ownedLocations: [UUID: FamilyShareLocation] = [:]
    private var memberSnapshots: [UUID: FamilyMemberSnapshot] = [:]
    private var activities: [FamilyShareActivity] = []
    private var pendingAttachmentDigests: [String: String] = [:]
    private let directoryOverride: URL?

    private enum PendingAttachmentSlot: String {
        case desired
        case base
    }

    private let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()
    private let decoder = PropertyListDecoder()

    init(directory: URL? = nil) {
        directoryOverride = directory
    }

    /// Reads the last received snapshot synchronously during app construction.
    /// The payload is already stored locally, so the first Home frame does not
    /// need to wait for SwiftData setup or a CloudKit round trip.
    static func cachedSharedPetsForLaunch(directory: URL? = nil) -> [FamilySharedPet] {
        let baseDirectory = directory ?? defaultDirectory
        let url = baseDirectory.appendingPathComponent("shared-pets.plist")
        guard let data = try? Data(contentsOf: url),
              let pets = try? PropertyListDecoder().decode([FamilySharedPet].self, from: data) else {
            return []
        }
        return pets.sorted {
            $0.pet.name.localizedStandardCompare($1.pet.name) == .orderedAscending
        }
    }

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Zoji/FamilySharing", isDirectory: true)
    }

    private var directory: URL {
        if let directoryOverride { return directoryOverride }
        return Self.defaultDirectory
    }

    private var pendingURL: URL { directory.appendingPathComponent("pending-changes.plist") }
    private var pendingAttachmentsURL: URL {
        directory.appendingPathComponent("pending-attachment-blobs", isDirectory: true)
    }
    private var cacheURL: URL { directory.appendingPathComponent("shared-pets.plist") }
    private var ownedURL: URL { directory.appendingPathComponent("owned-locations.plist") }
    private var membersURL: URL { directory.appendingPathComponent("member-snapshots.plist") }
    private var activitiesURL: URL { directory.appendingPathComponent("family-activities.plist") }

    func enqueue(_ change: FamilyPendingChange) throws {
        try loadIfNeeded()
        if change.kind == .deletePet {
            pendingChanges.removeAll { $0.petID == change.petID }
            pendingChanges.append(change)
        } else if [.savePet, .saveHealthRecord, .saveReminder].contains(change.kind),
           let earlier = pendingChanges.first(where: { $0.coalescingKey == change.coalescingKey }) {
            // Keep the earliest base and the latest desired value. This retains
            // three-way merge semantics without growing one queue item per edit.
            let coalesced = FamilyPendingChange(
                id: change.id,
                createdAt: change.createdAt,
                kind: change.kind,
                location: change.location,
                petID: change.petID,
                entityID: change.entityID,
                pet: change.pet,
                basePet: earlier.basePet ?? change.basePet,
                healthRecord: change.healthRecord,
                baseHealthRecord: earlier.baseHealthRecord ?? change.baseHealthRecord,
                reminder: change.reminder,
                baseReminder: earlier.baseReminder ?? change.baseReminder
            )
            pendingChanges.removeAll { $0.coalescingKey == change.coalescingKey }
            pendingChanges.append(coalesced)
        } else {
            pendingChanges.removeAll { $0.coalescingKey == change.coalescingKey }
            pendingChanges.append(change)
        }
        try persistPendingChanges()
    }

    func upsertCachedOwnedPet(_ pet: Pet, location: FamilyShareLocation) throws {
        try loadIfNeeded()
        guard let key = sharedPetCache.keys.first(where: { cachedID in
            guard let cached = sharedPetCache[cachedID] else { return false }
            return cached.location == location && cached.pet.id == pet.id
        }) else { return }
        sharedPetCache[key]?.payload.pet = pet
        try persistCache()
    }

    func nextPendingChange() throws -> FamilyPendingChange? {
        try loadIfNeeded()
        return pendingChanges.first
    }

    func markCompleted(_ id: UUID) throws {
        try loadIfNeeded()
        pendingChanges.removeAll { $0.id == id }
        try persistPendingChanges()
    }

    func allPendingChanges() throws -> [FamilyPendingChange] {
        try loadIfNeeded()
        return pendingChanges
    }

    func pendingCount() throws -> Int {
        try loadIfNeeded()
        return pendingChanges.count
    }

    func cachedSharedPets() throws -> [FamilySharedPet] {
        try loadIfNeeded()
        return Array(sharedPetCache.values)
    }

    func cache(_ pets: [FamilySharedPet]) throws {
        try loadIfNeeded()
        sharedPetCache = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0) })
        try persistCache()
    }

    func upsertCachedPet(_ pet: FamilySharedPet) throws {
        try loadIfNeeded()
        sharedPetCache[pet.id] = pet
        try persistCache()
    }

    func removeCachedPet(id: String) throws {
        try loadIfNeeded()
        sharedPetCache.removeValue(forKey: id)
        try persistCache()
    }

    /// A revoked share or write permission can never accept its queued edits.
    /// Remove only that destination so it cannot block changes for other pets.
    func discardPendingChanges(
        at location: FamilyShareLocation,
        removingCachedPet: Bool
    ) throws {
        try loadIfNeeded()
        pendingChanges.removeAll { $0.location == location }
        try persistPendingChanges()

        if removingCachedPet {
            sharedPetCache = sharedPetCache.filter { $0.value.location != location }
            try persistCache()
            ownedLocations = ownedLocations.filter { $0.value != location }
            try persistOwnedLocations()
        }
    }

    func registerOwned(_ registrations: [UUID: FamilyShareLocation]) throws {
        try loadIfNeeded()
        for (petID, location) in registrations {
            ownedLocations[petID] = location
        }
        try persistOwnedLocations()
    }

    /// Reconciles only the pets that were just checked against CloudKit. If a
    /// share was revoked outside the app, its stale upload destination and any
    /// queued writes must not keep retrying forever.
    func reconcileOwned(
        _ registrations: [UUID: FamilyShareLocation],
        checkedPetIDs: Set<UUID>
    ) throws {
        try loadIfNeeded()
        let noLongerShared = checkedPetIDs.subtracting(registrations.keys)
        for petID in noLongerShared {
            ownedLocations.removeValue(forKey: petID)
        }
        for (petID, location) in registrations {
            ownedLocations[petID] = location
        }
        if !noLongerShared.isEmpty {
            pendingChanges.removeAll { noLongerShared.contains($0.petID) }
            try persistPendingChanges()
        }
        try persistOwnedLocations()
    }

    func ownedLocation(for petID: UUID) throws -> FamilyShareLocation? {
        try loadIfNeeded()
        return ownedLocations[petID]
    }

    func ownedPetIDs() throws -> Set<UUID> {
        try loadIfNeeded()
        return Set(ownedLocations.keys)
    }

    @discardableResult
    func reconcileMembers(
        petID: UUID,
        petName: String,
        members: [FamilyShareMember],
        recordChanges: Bool = true
    ) throws -> [FamilyShareActivity] {
        try loadIfNeeded()
        let visibleMembers = members.filter { $0.role != .owner }
        let previous = memberSnapshots[petID]
        memberSnapshots[petID] = FamilyMemberSnapshot(
            petID: petID,
            petName: petName,
            members: visibleMembers
        )
        try persistMemberSnapshots()

        guard recordChanges, let previous else { return [] }
        let oldByID = Dictionary(uniqueKeysWithValues: previous.members.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: visibleMembers.map { ($0.id, $0) })
        var events: [FamilyShareActivity] = []

        for member in visibleMembers where member.status == .accepted {
            guard oldByID[member.id]?.status != .accepted else { continue }
            events.append(FamilyShareActivity(
                id: UUID(),
                petID: petID,
                petName: petName,
                memberName: member.displayName,
                kind: .joined,
                occurredAt: Date(),
                isAcknowledged: false,
                notificationDelivered: false
            ))
        }

        for oldMember in previous.members where oldMember.status == .accepted {
            let newStatus = newByID[oldMember.id]?.status
            guard newStatus == nil || newStatus == .removed else { continue }
            events.append(FamilyShareActivity(
                id: UUID(),
                petID: petID,
                petName: petName,
                memberName: oldMember.displayName,
                kind: .left,
                occurredAt: Date(),
                isAcknowledged: false,
                notificationDelivered: false
            ))
        }

        if !events.isEmpty {
            activities.insert(contentsOf: events, at: 0)
            activities = Array(activities.prefix(50))
            try persistActivities()
        }
        return events
    }

    func recentActivities() throws -> [FamilyShareActivity] {
        try loadIfNeeded()
        return activities.sorted { $0.occurredAt > $1.occurredAt }
    }

    func acknowledgeActivities() throws {
        try loadIfNeeded()
        for index in activities.indices {
            activities[index].isAcknowledged = true
        }
        try persistActivities()
    }

    func consumeUndeliveredActivities() throws -> [FamilyShareActivity] {
        try loadIfNeeded()
        let values = activities.filter { !$0.notificationDelivered }
        guard !values.isEmpty else { return [] }
        for index in activities.indices where !activities[index].notificationDelivered {
            activities[index].notificationDelivered = true
        }
        try persistActivities()
        return values
    }

    private func loadIfNeeded() throws {
        guard !didLoad else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var needsPendingMigration = false
        if FileManager.default.fileExists(atPath: pendingURL.path) {
            let data = try Data(contentsOf: pendingURL)
            let storedChanges = try decoder.decode([FamilyPendingChange].self, from: data)
            needsPendingMigration = storedChanges.contains { $0.attachmentStorageVersion == nil }
            pendingChanges = try storedChanges.map(hydratingPendingAttachments)
        }
        if let data = try? Data(contentsOf: cacheURL),
           let pets = try? decoder.decode([FamilySharedPet].self, from: data) {
            sharedPetCache = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0) })
        }
        if let data = try? Data(contentsOf: ownedURL),
           let values = try? decoder.decode([FamilyOwnedLocationRegistration].self, from: data) {
            ownedLocations = Dictionary(uniqueKeysWithValues: values.map { ($0.petID, $0.location) })
        }
        if let data = try? Data(contentsOf: membersURL),
           let values = try? decoder.decode([FamilyMemberSnapshot].self, from: data) {
            memberSnapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.petID, $0) })
        }
        if let data = try? Data(contentsOf: activitiesURL) {
            activities = (try? decoder.decode([FamilyShareActivity].self, from: data)) ?? []
        }
        didLoad = true
        if needsPendingMigration {
            do {
                try persistPendingChanges()
            } catch {
                didLoad = false
                throw error
            }
        }
    }

    private func persistPendingChanges() throws {
        try FileManager.default.createDirectory(
            at: pendingAttachmentsURL,
            withIntermediateDirectories: true
        )
        var retainedBlobPaths = Set<String>()
        let storedChanges = try pendingChanges.map { change in
            let desired = try externalizedRecord(
                change.healthRecord,
                changeID: change.id,
                slot: .desired,
                retainedBlobPaths: &retainedBlobPaths
            )
            let base = try externalizedRecord(
                change.baseHealthRecord,
                changeID: change.id,
                slot: .base,
                retainedBlobPaths: &retainedBlobPaths
            )
            return change.replacingQueuedHealthRecords(
                healthRecord: desired,
                baseHealthRecord: base,
                attachmentStorageVersion: 1
            )
        }
        try encoder.encode(storedChanges).write(to: pendingURL, options: .atomic)
        cleanupPendingAttachmentBlobs(retaining: retainedBlobPaths)
    }

    private func externalizedRecord(
        _ value: HealthRecord?,
        changeID: UUID,
        slot: PendingAttachmentSlot,
        retainedBlobPaths: inout Set<String>
    ) throws -> HealthRecord? {
        guard var record = value else { return nil }
        for index in record.attachments.indices {
            let attachment = record.attachments[index]
            let url = pendingAttachmentURL(
                changeID: changeID,
                slot: slot,
                attachmentID: attachment.id
            )
            let path = url.standardizedFileURL.path
            retainedBlobPaths.insert(path)
            let digest = Self.digest(of: attachment.data)
            if pendingAttachmentDigests[path] != digest ||
                !FileManager.default.fileExists(atPath: path) {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try attachment.data.write(to: url, options: .atomic)
                pendingAttachmentDigests[path] = digest
            }
            record.attachments[index].data = Data()
        }
        return record
    }

    private func hydratingPendingAttachments(_ change: FamilyPendingChange) throws -> FamilyPendingChange {
        guard change.attachmentStorageVersion == 1 else { return change }
        let desired = try hydratedRecord(change.healthRecord, changeID: change.id, slot: .desired)
        let base = try hydratedRecord(change.baseHealthRecord, changeID: change.id, slot: .base)
        return change.replacingQueuedHealthRecords(
            healthRecord: desired,
            baseHealthRecord: base,
            attachmentStorageVersion: 1
        )
    }

    private func hydratedRecord(
        _ value: HealthRecord?,
        changeID: UUID,
        slot: PendingAttachmentSlot
    ) throws -> HealthRecord? {
        guard var record = value else { return nil }
        for index in record.attachments.indices where record.attachments[index].data.isEmpty {
            let url = pendingAttachmentURL(
                changeID: changeID,
                slot: slot,
                attachmentID: record.attachments[index].id
            )
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            record.attachments[index].data = data
            pendingAttachmentDigests[url.standardizedFileURL.path] = Self.digest(of: data)
        }
        return record
    }

    private func pendingAttachmentURL(
        changeID: UUID,
        slot: PendingAttachmentSlot,
        attachmentID: UUID
    ) -> URL {
        pendingAttachmentsURL
            .appendingPathComponent(changeID.uuidString, isDirectory: true)
            .appendingPathComponent(slot.rawValue, isDirectory: true)
            .appendingPathComponent(attachmentID.uuidString)
            .appendingPathExtension("blob")
    }

    private func cleanupPendingAttachmentBlobs(retaining retainedPaths: Set<String>) {
        guard let enumerator = FileManager.default.enumerator(
            at: pendingAttachmentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var directories: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                directories.append(url)
            } else if !retainedPaths.contains(url.standardizedFileURL.path) {
                try? FileManager.default.removeItem(at: url)
                pendingAttachmentDigests.removeValue(forKey: url.standardizedFileURL.path)
            }
        }
        for url in directories.sorted(by: { $0.path.count > $1.path.count }) {
            guard (try? FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty) == true else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func persistCache() throws {
        try encoder.encode(Array(sharedPetCache.values)).write(to: cacheURL, options: .atomic)
    }

    private func persistOwnedLocations() throws {
        let values = ownedLocations.map { FamilyOwnedLocationRegistration(petID: $0.key, location: $0.value) }
        try encoder.encode(values).write(to: ownedURL, options: .atomic)
    }

    private func persistMemberSnapshots() throws {
        try encoder.encode(Array(memberSnapshots.values)).write(to: membersURL, options: .atomic)
    }

    private func persistActivities() throws {
        try encoder.encode(activities).write(to: activitiesURL, options: .atomic)
    }
}

struct FamilySyncAttempt: Sendable {
    let remainingCount: Int
    let errorDescription: String?
    let recoveries: [FamilySyncRecovery]
}

enum FamilySyncRecovery: Equatable, Sendable {
    case shareUnavailable(FamilyShareLocation)
    case writePermissionRevoked(FamilyShareLocation)

    var location: FamilyShareLocation {
        switch self {
        case .shareUnavailable(let location), .writePermissionRevoked(let location): location
        }
    }

    var isShareUnavailable: Bool {
        if case .shareUnavailable = self { return true }
        return false
    }
}

actor FamilySharingUploadCoordinator {
    static let shared = FamilySharingUploadCoordinator()

    private var activeTask: Task<FamilySyncAttempt, Never>?

    func synchronize() async -> FamilySyncAttempt {
        if let activeTask {
            return await activeTask.value
        }

        let task = Task<FamilySyncAttempt, Never> {
            var recoveries: [FamilySyncRecovery] = []
            while !Task.isCancelled {
                do {
                    guard let change = try await FamilySharingLocalStore.shared.nextPendingChange() else {
                        return FamilySyncAttempt(
                            remainingCount: 0,
                            errorDescription: nil,
                            recoveries: recoveries
                        )
                    }
                    try await FamilySharingService.shared.uploadPendingChange(change)
                    try await FamilySharingLocalStore.shared.markCompleted(change.id)
                } catch {
                    if let change = try? await FamilySharingLocalStore.shared.nextPendingChange(),
                       let recovery = FamilySharingService.syncRecovery(
                           for: error,
                           location: change.location
                       ) {
                        do {
                            try await FamilySharingLocalStore.shared.discardPendingChanges(
                                at: change.location,
                                removingCachedPet: recovery.isShareUnavailable
                            )
                        } catch {
                            let remaining = (try? await FamilySharingLocalStore.shared.pendingCount()) ?? 1
                            return FamilySyncAttempt(
                                remainingCount: remaining,
                                errorDescription: error.localizedDescription,
                                recoveries: recoveries
                            )
                        }
                        if !recoveries.contains(recovery) {
                            recoveries.append(recovery)
                        }
                        continue
                    }
                    let remaining = (try? await FamilySharingLocalStore.shared.pendingCount()) ?? 1
                    return FamilySyncAttempt(
                        remainingCount: remaining,
                        errorDescription: error.localizedDescription,
                        recoveries: recoveries
                    )
                }
            }
            let remaining = (try? await FamilySharingLocalStore.shared.pendingCount()) ?? 0
            return FamilySyncAttempt(
                remainingCount: remaining,
                errorDescription: nil,
                recoveries: recoveries
            )
        }
        activeTask = task
        let result = await task.value
        activeTask = nil
        return result
    }
}

struct FamilyPetShareItem: Transferable, Sendable {
    let payload: FamilyPetSharePayload
    let invitedRole: FamilyAccessRole?
    let preparedShare: CKShare?

    init(
        payload: FamilyPetSharePayload,
        invitedRole: FamilyAccessRole? = nil,
        preparedShare: CKShare? = nil
    ) {
        self.payload = payload
        self.invitedRole = invitedRole
        self.preparedShare = preparedShare
    }

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            let permissionOptions: CKSharingParticipantPermissionOption = switch item.invitedRole {
            case .editor: .readWrite
            case .viewer: .readOnly
            case .owner, nil: .any
            }
            let options = CKAllowedSharingOptions(
                allowedParticipantPermissionOptions: permissionOptions,
                allowedParticipantAccessOptions: .specifiedRecipientsOnly
            )
            if let preparedShare = item.preparedShare {
                return .existing(
                    preparedShare,
                    container: CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier),
                    allowedSharingOptions: options
                )
            }
            return .prepareShare(
                container: CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier),
                allowedSharingOptions: options
            ) {
                try await FamilySharingService.shared.prepareOrUpdateShare(payload: item.payload)
            }
        }
    }
}

actor FamilySharingService {
    static let shared = FamilySharingService()
    static let didAcceptShareNotification = Notification.Name("ZojiFamilySharingDidAcceptShare")
    static let pendingChangesDidUpdateNotification = Notification.Name("ZojiFamilyPendingChangesDidUpdate")

    private enum RecordSchema {
        static let petSnapshot = "ZojiFamilyPetSnapshot"
        static let healthRecord = "ZojiFamilyHealthRecord"
        static let attachment = "ZojiFamilyAttachment"
        static let reminder = "ZojiFamilyReminder"

        static let payloadAsset = "payloadAsset"
        static let petAsset = "petAsset"
        static let bodyData = "bodyData"
        static let attachmentAsset = "attachmentAsset"
        static let petID = "petID"
        static let petName = "petName"
        static let entityID = "entityID"
        static let healthRecordID = "healthRecordID"
        static let attachmentKind = "attachmentKind"
        static let originalName = "originalName"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let schemaVersion = "schemaVersion"
        static let contentReady = "contentReady"

        /// Fields needed to discover and mutate zone records without asking
        /// CloudKit to materialize any CKAsset files.
        static let metadataKeys: [CKRecord.FieldKey] = [
            bodyData,
            petID,
            petName,
            entityID,
            healthRecordID,
            attachmentKind,
            originalName,
            createdAt,
            updatedAt,
            schemaVersion,
            contentReady,
        ]

        static let attachmentContentKeys: [CKRecord.FieldKey] = [
            entityID,
            healthRecordID,
            attachmentKind,
            originalName,
            createdAt,
            updatedAt,
            attachmentAsset,
        ]
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(container: CKContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)) {
        self.container = container
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    nonisolated static func syncRecovery(
        for error: Error,
        location: FamilyShareLocation
    ) -> FamilySyncRecovery? {
        let codes = cloudKitErrorCodes(in: error)
        if codes.contains(where: { $0 == .zoneNotFound || $0 == .unknownItem }) {
            return .shareUnavailable(location)
        }
        if codes.contains(where: { $0 == .permissionFailure }) {
            return .writePermissionRevoked(location)
        }
        return nil
    }

    private nonisolated static func cloudKitErrorCodes(in error: Error) -> [CKError.Code] {
        guard let cloudError = error as? CKError else { return [] }
        var codes = [cloudError.code]
        if cloudError.code == .partialFailure,
           let partialErrors = cloudError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for nestedError in partialErrors.values {
                codes.append(contentsOf: cloudKitErrorCodes(in: nestedError))
            }
        }
        return codes
    }

    func prepareOrUpdateShare(payload: FamilyPetSharePayload) async throws -> CKShare {
        try payload.validate()
        let zoneID = Self.zoneID(for: payload.pet.id)
        try await ensureZone(zoneID)

        let rootID = Self.rootRecordID(for: payload.pet.id, zoneID: zoneID)
        let shareID = Self.shareRecordID(for: payload.pet.id, zoneID: zoneID)

        // Reuse an existing share only after its full history is confirmed ready.
        // Shares created by an older build have no readiness marker, so they are
        // checked once and then become fast for every later invitation.
        if let existingShare = try await existingRecord(id: shareID, in: privateDatabase) as? CKShare {
            let expectedTitle = "\(payload.pet.name)的宠物档案"
            var needsSaving = false
            if existingShare[CKShare.SystemFieldKey.title] as? String != expectedTitle {
                existingShare[CKShare.SystemFieldKey.title] = expectedTitle as CKRecordValue
                needsSaving = true
            }
            if (existingShare[RecordSchema.contentReady] as? Int64) != 1 {
                try await seedMissingStructuredRecords(payload: payload, zoneID: zoneID)
                existingShare[RecordSchema.contentReady] = Int64(1) as CKRecordValue
                needsSaving = true
            }
            guard needsSaving else { return existingShare }
            let result = try await privateDatabase.modifyRecords(
                saving: [existingShare],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )
            try Self.validateSaveResult(result.saveResults, recordID: shareID)
            if case .success(let savedShare)? = result.saveResults[shareID],
               let share = savedShare as? CKShare {
                return share
            }
            return existingShare
        }

        let existingRoot = try await existingRecord(id: rootID, in: privateDatabase)
        let rootRecord = existingRoot ?? CKRecord(recordType: RecordSchema.petSnapshot, recordID: rootID)
        var temporaryURLs: [URL] = []
        defer { removeTemporaryFiles(temporaryURLs) }

        rootRecord[RecordSchema.petID] = payload.pet.id.uuidString as CKRecordValue
        rootRecord[RecordSchema.petName] = payload.pet.name as CKRecordValue
        rootRecord[RecordSchema.schemaVersion] = FamilyPetSharePayload.currentSchemaVersion as CKRecordValue
        rootRecord[RecordSchema.updatedAt] = Date() as CKRecordValue

        // Keep a small compatibility snapshot. Attachments are structured
        // records and must not block the invitation card from becoming ready.
        let lightweightPayload = FamilyPetSharePayload(
            pet: payload.pet,
            records: payload.records.map { record in
                var record = record
                record.attachments = []
                return record
            },
            reminders: payload.reminders
        )
        let legacyURL = try makeTemporaryFile(data: encoder.encode(lightweightPayload), extension: "json")
        temporaryURLs.append(legacyURL)
        rootRecord[RecordSchema.payloadAsset] = CKAsset(fileURL: legacyURL)

        if existingRoot?[RecordSchema.petAsset] == nil {
            let petURL = try makeTemporaryFile(data: encoder.encode(payload.pet), extension: "json")
            temporaryURLs.append(petURL)
            rootRecord[RecordSchema.petAsset] = CKAsset(fileURL: petURL)
        }

        let newShare = CKShare(rootRecord: rootRecord, shareID: shareID)
        newShare[CKShare.SystemFieldKey.title] = "\(payload.pet.name)的宠物档案" as CKRecordValue
        newShare[CKShare.SystemFieldKey.shareType] = "com.haoqianglyu.zoji.pet" as CKRecordValue
        newShare[RecordSchema.contentReady] = Int64(0) as CKRecordValue
        newShare.publicPermission = .none

        let result = try await privateDatabase.modifyRecords(
            saving: [rootRecord, newShare],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        try Self.validateSaveResult(result.saveResults, recordID: rootID)
        guard case .success(let savedShare)? = result.saveResults[shareID],
              let share = savedShare as? CKShare else {
            throw FamilySharingError.shareCreationFailed
        }

        // A first invitation is not offered until every existing record and
        // attachment is present. This prevents an invitee from opening a partial
        // pet archive if iOS suspends the owner after switching to Messages.
        try await seedMissingStructuredRecords(payload: payload, zoneID: zoneID)
        share[RecordSchema.contentReady] = Int64(1) as CKRecordValue
        let readyResult = try await privateDatabase.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        try Self.validateSaveResult(readyResult.saveResults, recordID: shareID)
        if case .success(let readyShare)? = readyResult.saveResults[shareID],
           let preparedShare = readyShare as? CKShare {
            return preparedShare
        }
        return share
    }

    func accept(metadata: CKShare.Metadata) async throws {
        let results = try await container.accept([metadata])
        guard case .success? = results[metadata] else {
            if case .failure(let error)? = results[metadata] { throw error }
            throw FamilySharingError.acceptanceFailed
        }
    }

    func fetchSharedPets() async throws -> [FamilySharedPet] {
        let zoneIDs = try await fetchAllZoneIDs(in: sharedDatabase)
        var sharedPets: [FamilySharedPet] = []
        for zoneID in zoneIDs {
            if let pet = try await fetchPet(zoneID: zoneID, databaseScope: .shared) {
                sharedPets.append(pet)
            }
        }
        return sharedPets.sorted { $0.pet.name.localizedStandardCompare($1.pet.name) == .orderedAscending }
    }

    func fetchOwnedSharedPets(petNames: [UUID: String]) async throws -> [FamilySharedPet] {
        var pets: [FamilySharedPet] = []
        var registrations: [UUID: FamilyShareLocation] = [:]
        var successfullyCheckedIDs = Set<UUID>()
        for (petID, petName) in petNames {
            let zoneID = Self.zoneID(for: petID)
            let shareID = Self.shareRecordID(for: petID, zoneID: zoneID)
            let record = try await existingRecord(id: shareID, in: privateDatabase)
            successfullyCheckedIDs.insert(petID)
            guard let share = record as? CKShare else {
                _ = try? await FamilySharingLocalStore.shared.reconcileMembers(
                    petID: petID,
                    petName: petName,
                    members: []
                )
                continue
            }
            _ = try? await FamilySharingLocalStore.shared.reconcileMembers(
                petID: petID,
                petName: petName,
                members: Self.members(from: share)
            )
            guard Self.hasInvitedParticipants(share) else { continue }
            let location = FamilyShareLocation(
                zoneName: zoneID.zoneName,
                zoneOwnerName: zoneID.ownerName,
                databaseScope: .ownerPrivate
            )
            registrations[petID] = location
            if let pet = try await fetchPet(zoneID: zoneID, databaseScope: .ownerPrivate) {
                pets.append(pet)
            }
        }
        try? await FamilySharingLocalStore.shared.reconcileOwned(
            registrations,
            checkedPetIDs: successfullyCheckedIDs
        )
        return pets
    }

    func fetchPet(location: FamilyShareLocation) async throws -> FamilySharedPet? {
        try await fetchPet(zoneID: location.zoneID, databaseScope: location.databaseScope)
    }

    func updateMemberPermission(
        petID: UUID,
        participantID: String,
        role: FamilyAccessRole
    ) async throws -> FamilySharedPet {
        guard role == .editor || role == .viewer else { throw FamilySharingError.invalidMemberOperation }
        let share = try await mutateOwnedShare(petID: petID) { share in
            guard let participant = share.participants.first(where: {
                $0.participantID == participantID && $0.role != .owner
            }) else {
                throw FamilySharingError.memberNotFound
            }
            participant.permission = role == .editor ? .readWrite : .readOnly
        }
        let members = Self.members(from: share)
        guard let pet = try await fetchPet(
            zoneID: Self.zoneID(for: petID),
            databaseScope: .ownerPrivate
        ) else {
            throw FamilySharingError.sharedPetNotFound
        }
        var updated = pet
        updated.members = members
        return updated
    }

    func removeMember(
        petID: UUID,
        participantID: String
    ) async throws -> FamilySharedPet {
        let share = try await mutateOwnedShare(petID: petID) { share in
            guard let participant = share.participants.first(where: {
                $0.participantID == participantID && $0.role != .owner
            }) else {
                throw FamilySharingError.memberNotFound
            }
            share.removeParticipant(participant)
        }
        let members = Self.members(from: share)
        guard let pet = try await fetchPet(
            zoneID: Self.zoneID(for: petID),
            databaseScope: .ownerPrivate
        ) else {
            throw FamilySharingError.sharedPetNotFound
        }
        var updated = pet
        updated.members = members
        return updated
    }

    private func mutateOwnedShare(
        petID: UUID,
        mutation: (CKShare) throws -> Void
    ) async throws -> CKShare {
        let zoneID = Self.zoneID(for: petID)
        let shareID = Self.shareRecordID(for: petID, zoneID: zoneID)
        for attempt in 0 ..< 2 {
            guard let share = try await existingRecord(id: shareID, in: privateDatabase) as? CKShare else {
                throw FamilySharingError.sharedPetNotFound
            }
            try mutation(share)
            do {
                let result = try await privateDatabase.modifyRecords(
                    saving: [share],
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: true
                )
                try Self.validateSaveResult(result.saveResults, recordID: shareID)
                guard case .success(let saved)? = result.saveResults[shareID],
                      let savedShare = saved as? CKShare else {
                    throw FamilySharingError.shareCreationFailed
                }
                return savedShare
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
        throw FamilySharingError.editConflict
    }

    /// Removes only the current participant from a family share. CloudKit treats
    /// a participant deleting the CKShare record as leaving that share; the
    /// owner's pet hierarchy and every other participant remain untouched.
    func leaveShare(petID: UUID, location: FamilyShareLocation) async throws {
        guard location.databaseScope == .shared else {
            throw FamilySharingError.ownerCannotLeave
        }
        let rootID = Self.rootRecordID(for: petID, zoneID: location.zoneID)
        guard let root = try await existingRecord(id: rootID, in: sharedDatabase),
              let referencedShareID = root.share?.recordID else {
            throw FamilySharingError.sharedPetNotFound
        }
        let shareID = Self.resolvedShareRecordID(
            referencedShareID: referencedShareID,
            sharedZoneID: location.zoneID,
            databaseScope: .shared
        )

        let result = try await sharedDatabase.modifyRecords(
            saving: [],
            deleting: [shareID],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        if case .failure(let error)? = result.deleteResults[shareID] {
            throw error
        }
    }

    func ownedSharedPetIDs(_ petIDs: [UUID]) async -> Set<UUID> {
        var sharedIDs = Set<UUID>()
        var registrations: [UUID: FamilyShareLocation] = [:]
        var successfullyCheckedIDs = Set<UUID>()
        let cachedIDs = (try? await FamilySharingLocalStore.shared.ownedPetIDs()) ?? []
        for petID in petIDs {
            let zoneID = Self.zoneID(for: petID)
            let shareID = Self.shareRecordID(for: petID, zoneID: zoneID)
            do {
                let existingShare = try await existingRecord(id: shareID, in: privateDatabase)
                successfullyCheckedIDs.insert(petID)
                if let share = existingShare as? CKShare,
                   Self.hasInvitedParticipants(share) {
                    sharedIDs.insert(petID)
                    registrations[petID] = FamilyShareLocation(
                        zoneName: zoneID.zoneName,
                        zoneOwnerName: zoneID.ownerName,
                        databaseScope: .ownerPrivate
                    )
                }
            } catch {
                // A network/account failure is not proof that sharing stopped.
                // Keep the last verified state until CloudKit can be checked.
                if cachedIDs.contains(petID),
                   let cachedLocation = try? await FamilySharingLocalStore.shared.ownedLocation(for: petID) {
                    sharedIDs.insert(petID)
                    registrations[petID] = cachedLocation
                }
            }
        }
        try? await FamilySharingLocalStore.shared.reconcileOwned(
            registrations,
            checkedPetIDs: successfullyCheckedIDs
        )
        return sharedIDs
    }

    func ownedLocation(for petID: UUID) async -> FamilyShareLocation? {
        if let cached = try? await FamilySharingLocalStore.shared.ownedLocation(for: petID) {
            return cached
        }
        let zoneID = Self.zoneID(for: petID)
        let shareID = Self.shareRecordID(for: petID, zoneID: zoneID)
        guard let record = try? await existingRecord(id: shareID, in: privateDatabase),
              let share = record as? CKShare,
              Self.hasInvitedParticipants(share) else {
            return nil
        }
        let location = FamilyShareLocation(
            zoneName: zoneID.zoneName,
            zoneOwnerName: zoneID.ownerName,
            databaseScope: .ownerPrivate
        )
        try? await FamilySharingLocalStore.shared.registerOwned([petID: location])
        return location
    }

    /// Resolves the upload destination for an owner-side mutation. A failed
    /// CloudKit lookup is deliberately different from a successful "not
    /// shared" result: while offline, keep an outbox item addressed to the
    /// deterministic owner zone so the edit cannot fall out of synchronization.
    func ownedMutationLocation(for petID: UUID) async -> FamilyShareLocation? {
        if let cached = try? await FamilySharingLocalStore.shared.ownedLocation(for: petID) {
            return cached
        }
        let zoneID = Self.zoneID(for: petID)
        let candidate = FamilyShareLocation(
            zoneName: zoneID.zoneName,
            zoneOwnerName: zoneID.ownerName,
            databaseScope: .ownerPrivate
        )
        let shareID = Self.shareRecordID(for: petID, zoneID: zoneID)
        do {
            guard let share = try await existingRecord(id: shareID, in: privateDatabase) as? CKShare,
                  Self.hasInvitedParticipants(share) else {
                return nil
            }
            try? await FamilySharingLocalStore.shared.registerOwned([petID: candidate])
            return candidate
        } catch {
            return candidate
        }
    }

    func uploadPendingChange(_ change: FamilyPendingChange) async throws {
        switch change.kind {
        case .savePet:
            guard let pet = change.pet else { throw FamilySharingError.invalidPayload }
            try await upsertPet(pet, replacing: change.basePet, location: change.location)
        case .deletePet:
            try await deleteOwnedPet(petID: change.petID, location: change.location)
        case .saveHealthRecord:
            guard let record = change.healthRecord else { throw FamilySharingError.invalidPayload }
            try await upsertHealthRecord(
                record,
                replacing: change.baseHealthRecord,
                location: change.location
            )
        case .deleteHealthRecord:
            guard let record = change.healthRecord else { throw FamilySharingError.invalidPayload }
            try await deleteHealthRecord(record, location: change.location)
        case .saveReminder:
            guard let reminder = change.reminder else { throw FamilySharingError.invalidPayload }
            try await upsertReminder(
                reminder,
                replacing: change.baseReminder,
                location: change.location
            )
        case .deleteReminder:
            guard let reminder = change.reminder else { throw FamilySharingError.invalidPayload }
            try await deleteReminder(reminder, location: change.location)
        case .completeReminder:
            guard let reminder = change.reminder,
                  let baseReminder = change.baseReminder,
                  let record = change.healthRecord else {
                throw FamilySharingError.invalidPayload
            }
            try await uploadReminderCompletion(
                reminder: reminder,
                replacing: baseReminder,
                record: record,
                location: change.location
            )
        }
    }

    func deleteOwnedPet(petID: UUID, location: FamilyShareLocation) async throws {
        guard location.databaseScope == .ownerPrivate else {
            throw FamilySharingError.ownerOnly
        }
        do {
            _ = try await privateDatabase.deleteRecordZone(withID: location.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // The desired end state is already present.
        }
        try? await FamilySharingLocalStore.shared.discardPendingChanges(
            at: location,
            removingCachedPet: true
        )
    }

    /// Migrates old snapshot shares without overwriting edits already made in the
    /// structured records by another family member.
    func refreshOwnedShares(payloads: [FamilyPetSharePayload]) async {
        let sharedIDs = await ownedSharedPetIDs(payloads.map(\.pet.id))
        for payload in payloads where sharedIDs.contains(payload.pet.id) {
            let zoneID = Self.zoneID(for: payload.pet.id)
            let shareID = Self.shareRecordID(for: payload.pet.id, zoneID: zoneID)
            guard let share = try? await existingRecord(id: shareID, in: privateDatabase) as? CKShare,
                  (share[RecordSchema.contentReady] as? Int64) != 1 else { continue }
            do {
                try await seedMissingStructuredRecords(payload: payload, zoneID: zoneID)
                share[RecordSchema.contentReady] = Int64(1) as CKRecordValue
                let result = try await privateDatabase.modifyRecords(
                    saving: [share],
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: true
                )
                try Self.validateSaveResult(result.saveResults, recordID: shareID)
            } catch {
                // Invitation preparation will retry and surface the error.
            }
        }
    }

    func upsertPet(_ pet: Pet, replacing basePet: Pet?, location: FamilyShareLocation) async throws {
        let database = database(for: location.databaseScope)
        let rootID = Self.rootRecordID(for: pet.id, zoneID: location.zoneID)
        for attempt in 0 ..< 2 {
            guard let root = try await existingRecord(id: rootID, in: database) else {
                throw FamilySharingError.sharedPetNotFound
            }
            let serverPet: Pet
            if let asset = root[RecordSchema.petAsset] as? CKAsset, let url = asset.fileURL {
                serverPet = try decodeAsset(Pet.self, from: url)
            } else {
                serverPet = pet
            }
            let mergedPet = Self.mergingPetChange(server: serverPet, desired: pet, base: basePet)
            let url = try makeTemporaryFile(data: encoder.encode(mergedPet), extension: "json")
            defer { removeTemporaryFiles([url]) }
            root[RecordSchema.petAsset] = CKAsset(fileURL: url)
            root[RecordSchema.petName] = mergedPet.name as CKRecordValue
            root[RecordSchema.updatedAt] = Date() as CKRecordValue

            do {
                let result = try await database.modifyRecords(
                    saving: [root],
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: true
                )
                try Self.validateSaveResult(result.saveResults, recordID: rootID)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
        throw FamilySharingError.editConflict
    }

    nonisolated static func mergingPetChange(server: Pet, desired: Pet, base: Pet?) -> Pet {
        var merged = desired
        var entries = Dictionary(uniqueKeysWithValues: server.sortedWeightEntries.map { ($0.id, $0) })
        let desiredEntries = Dictionary(uniqueKeysWithValues: desired.sortedWeightEntries.map { ($0.id, $0) })
        let baseEntries = Dictionary(uniqueKeysWithValues: (base?.sortedWeightEntries ?? []).map { ($0.id, $0) })

        for (id, desiredEntry) in desiredEntries {
            if baseEntries[id] == nil || baseEntries[id] != desiredEntry {
                entries[id] = desiredEntry
            }
        }
        if base != nil {
            for id in baseEntries.keys where desiredEntries[id] == nil {
                entries.removeValue(forKey: id)
            }
        }

        let sortedEntries = entries.values.sorted { $0.measuredAt < $1.measuredAt }
        merged.weightEntries = sortedEntries
        merged.weightKilograms = sortedEntries.last?.kilograms
        return merged
    }

    nonisolated static func mergingHealthRecordChange(
        server: HealthRecord,
        desired: HealthRecord,
        base: HealthRecord?
    ) -> HealthRecord {
        guard let base else {
            var merged = desired
            var attachments = Dictionary(uniqueKeysWithValues: server.attachments.map { ($0.id, $0) })
            for attachment in desired.attachments {
                attachments[attachment.id] = attachment
            }
            merged.attachments = attachments.values.sorted { $0.createdAt < $1.createdAt }
            return merged
        }

        var merged = server
        if desired.kind != base.kind { merged.kind = desired.kind }
        if desired.title != base.title { merged.title = desired.title }
        if desired.occurredAt != base.occurredAt { merged.occurredAt = desired.occurredAt }
        if desired.providerName != base.providerName { merged.providerName = desired.providerName }
        if desired.costCents != base.costCents { merged.costCents = desired.costCents }
        if desired.currencyCode != base.currencyCode { merged.currencyCode = desired.currencyCode }
        if desired.timeZoneIdentifier != base.timeZoneIdentifier {
            merged.timeZoneIdentifier = desired.timeZoneIdentifier
        }
        if desired.notes != base.notes { merged.notes = desired.notes }

        let baseAttachments = Dictionary(uniqueKeysWithValues: base.attachments.map { ($0.id, $0) })
        let desiredAttachments = Dictionary(uniqueKeysWithValues: desired.attachments.map { ($0.id, $0) })
        var attachments = Dictionary(uniqueKeysWithValues: server.attachments.map { ($0.id, $0) })
        for id in baseAttachments.keys where desiredAttachments[id] == nil {
            attachments.removeValue(forKey: id)
        }
        for (id, attachment) in desiredAttachments where baseAttachments[id] != attachment {
            attachments[id] = attachment
        }
        merged.attachments = attachments.values.sorted { $0.createdAt < $1.createdAt }
        return merged
    }

    nonisolated static func mergingReminderChange(
        server: ReminderItem,
        desired: ReminderItem,
        base: ReminderItem?
    ) -> ReminderItem {
        guard let base else {
            var merged = desired
            if let serverCompletedAt = server.lastCompletedAt,
               desired.lastCompletedAt.map({ serverCompletedAt > $0 }) ?? true {
                merged.dueAt = server.dueAt
                merged.isEnabled = server.isEnabled
                merged.lastCompletedAt = serverCompletedAt
            }
            return merged
        }

        var merged = server
        if desired.sourceRecordID != base.sourceRecordID { merged.sourceRecordID = desired.sourceRecordID }
        if desired.title != base.title { merged.title = desired.title }
        if desired.kind != base.kind { merged.kind = desired.kind }
        if desired.scheduleType != base.scheduleType { merged.scheduleType = desired.scheduleType }
        if desired.intervalValue != base.intervalValue { merged.intervalValue = desired.intervalValue }
        if desired.advanceDays != base.advanceDays { merged.advanceDays = desired.advanceDays }

        let serverCompletedSinceBase = server.lastCompletedAt != base.lastCompletedAt
        let desiredCompletedSinceBase = desired.lastCompletedAt != base.lastCompletedAt
        if serverCompletedSinceBase && !desiredCompletedSinceBase {
            merged.dueAt = server.dueAt
            merged.isEnabled = server.isEnabled
            merged.lastCompletedAt = server.lastCompletedAt
        } else if serverCompletedSinceBase && desiredCompletedSinceBase {
            let serverDate = server.lastCompletedAt ?? .distantPast
            let desiredDate = desired.lastCompletedAt ?? .distantPast
            if desiredDate >= serverDate {
                merged.dueAt = desired.dueAt
                merged.isEnabled = desired.isEnabled
                merged.lastCompletedAt = desired.lastCompletedAt
            }
        } else {
            if desired.dueAt != base.dueAt { merged.dueAt = desired.dueAt }
            if desired.isEnabled != base.isEnabled { merged.isEnabled = desired.isEnabled }
            if desired.lastCompletedAt != base.lastCompletedAt {
                merged.lastCompletedAt = desired.lastCompletedAt
            }
        }
        return merged
    }

    func upsertHealthRecord(
        _ record: HealthRecord,
        replacing baseRecord: HealthRecord?,
        location: FamilyShareLocation
    ) async throws {
        try HealthRecordAttachmentPolicy.validate(record.attachments)
        let database = database(for: location.databaseScope)
        let zoneID = location.zoneID
        let rootID = Self.rootRecordID(for: record.petID, zoneID: zoneID)
        let recordID = Self.healthRecordID(for: record.id, zoneID: zoneID)
        for attempt in 0 ..< 2 {
            var zoneRecords = try await fetchAllRecords(
                zoneID: zoneID,
                in: database,
                desiredKeys: RecordSchema.metadataKeys
            )
            zoneRecords = try await hydratingAttachmentAssets(
                for: record.id,
                in: zoneRecords,
                database: database
            )
            let serverRecord = try decodeHealthRecord(id: record.id, zoneID: zoneID, from: zoneRecords)
            let merged = serverRecord.map {
                Self.mergingHealthRecordChange(server: $0, desired: record, base: baseRecord)
            } ?? record
            try HealthRecordAttachmentPolicy.validate(merged.attachments)

            let body = HealthRecord(
                id: merged.id,
                petID: merged.petID,
                kind: merged.kind,
                title: merged.title,
                occurredAt: merged.occurredAt,
                providerName: merged.providerName,
                costCents: merged.costCents,
                currencyCode: merged.currencyCode,
                timeZoneIdentifier: merged.timeZoneIdentifier,
                notes: merged.notes,
                attachments: []
            )
            let cloudRecord = zoneRecords[recordID]
                ?? CKRecord(recordType: RecordSchema.healthRecord, recordID: recordID)
            cloudRecord.parent = CKRecord.Reference(recordID: rootID, action: .none)
            cloudRecord[RecordSchema.entityID] = merged.id.uuidString as CKRecordValue
            cloudRecord[RecordSchema.petID] = merged.petID.uuidString as CKRecordValue
            cloudRecord[RecordSchema.bodyData] = try encoder.encode(body) as CKRecordValue
            cloudRecord[RecordSchema.updatedAt] = Date() as CKRecordValue

            let existingAttachments = zoneRecords.values.filter {
                $0.recordType == RecordSchema.attachment
                    && ($0[RecordSchema.healthRecordID] as? String) == merged.id.uuidString
            }
            let retainedIDs = Set(merged.attachments.map(\.id))
            let deleting = existingAttachments.compactMap { cloudAttachment -> CKRecord.ID? in
                guard let rawID = cloudAttachment[RecordSchema.entityID] as? String,
                      let id = UUID(uuidString: rawID),
                      !retainedIDs.contains(id) else { return nil }
                return cloudAttachment.recordID
            }

            var saving: [CKRecord] = [cloudRecord]
            var temporaryURLs: [URL] = []
            defer { removeTemporaryFiles(temporaryURLs) }
            for attachment in merged.attachments {
                let id = Self.attachmentID(for: attachment.id, zoneID: zoneID)
                let child = zoneRecords[id] ?? CKRecord(recordType: RecordSchema.attachment, recordID: id)
                child.parent = CKRecord.Reference(recordID: recordID, action: .none)
                child[RecordSchema.entityID] = attachment.id.uuidString as CKRecordValue
                child[RecordSchema.healthRecordID] = merged.id.uuidString as CKRecordValue
                child[RecordSchema.attachmentKind] = attachment.kind.rawValue as CKRecordValue
                child[RecordSchema.originalName] = attachment.originalName as CKRecordValue
                child[RecordSchema.createdAt] = attachment.createdAt as CKRecordValue
                child[RecordSchema.updatedAt] = Date() as CKRecordValue
                let fileExtension = attachment.kind == .pdf ? "pdf" : "jpg"
                let url = try makeTemporaryFile(data: attachment.data, extension: fileExtension)
                temporaryURLs.append(url)
                child[RecordSchema.attachmentAsset] = CKAsset(fileURL: url)
                saving.append(child)
            }

            do {
                try await saveRecords(saving, deleting: deleting, in: database, retryingConflicts: false)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
    }

    func deleteHealthRecord(_ record: HealthRecord, location: FamilyShareLocation) async throws {
        let database = database(for: location.databaseScope)
        let zoneRecords = try await fetchAllRecords(
            zoneID: location.zoneID,
            in: database,
            desiredKeys: RecordSchema.metadataKeys
        )
        let recordID = Self.healthRecordID(for: record.id, zoneID: location.zoneID)
        var deleting = zoneRecords[recordID] == nil ? [] : [recordID]
        deleting.append(contentsOf: zoneRecords.values.compactMap { child in
            guard child.recordType == RecordSchema.attachment,
                  (child[RecordSchema.healthRecordID] as? String) == record.id.uuidString else {
                return nil
            }
            return child.recordID
        })
        guard !deleting.isEmpty else { return }
        try await saveRecords([], deleting: deleting, in: database, retryingConflicts: false)
    }

    func upsertReminder(
        _ reminder: ReminderItem,
        replacing baseReminder: ReminderItem?,
        location: FamilyShareLocation
    ) async throws {
        let database = database(for: location.databaseScope)
        let rootID = Self.rootRecordID(for: reminder.petID, zoneID: location.zoneID)
        let id = Self.reminderID(for: reminder.id, zoneID: location.zoneID)
        for attempt in 0 ..< 2 {
            let cloudRecord = try await existingRecord(id: id, in: database)
                ?? CKRecord(recordType: RecordSchema.reminder, recordID: id)
            let serverReminder: ReminderItem? = if let data = cloudRecord[RecordSchema.bodyData] as? Data {
                try decoder.decode(ReminderItem.self, from: data)
            } else { nil }
            let merged = serverReminder.map {
                Self.mergingReminderChange(server: $0, desired: reminder, base: baseReminder)
            } ?? reminder
            cloudRecord.parent = CKRecord.Reference(recordID: rootID, action: .none)
            cloudRecord[RecordSchema.entityID] = merged.id.uuidString as CKRecordValue
            cloudRecord[RecordSchema.petID] = merged.petID.uuidString as CKRecordValue
            cloudRecord[RecordSchema.bodyData] = try encoder.encode(merged) as CKRecordValue
            cloudRecord[RecordSchema.updatedAt] = Date() as CKRecordValue
            do {
                try await saveRecords([cloudRecord], deleting: [], in: database, retryingConflicts: false)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
    }

    func deleteReminder(_ reminder: ReminderItem, location: FamilyShareLocation) async throws {
        let id = Self.reminderID(for: reminder.id, zoneID: location.zoneID)
        let database = database(for: location.databaseScope)
        guard try await existingRecord(id: id, in: database) != nil else { return }
        try await saveRecords([], deleting: [id], in: database, retryingConflicts: false)
    }

    func completeReminder(
        id: UUID,
        petID: UUID,
        location: FamilyShareLocation
    ) async throws -> FamilyReminderCompletion {
        let database = database(for: location.databaseScope)
        let cloudID = Self.reminderID(for: id, zoneID: location.zoneID)

        for attempt in 0 ..< 2 {
            guard let cloudReminder = try await existingRecord(id: cloudID, in: database),
                  let data = cloudReminder[RecordSchema.bodyData] as? Data else {
                throw FamilySharingError.sharedReminderNotFound
            }
            var reminder = try decoder.decode(ReminderItem.self, from: data)
            guard reminder.petID == petID else { throw FamilySharingError.invalidPayload }
            guard !reminder.isCompletionLocked() else {
                throw ReminderCompletionError.currentCycleAlreadyCompleted
            }

            let completedAt = Date()
            reminder.lastCompletedAt = completedAt
            let nextDueAt = ReminderCalculator.nextDueDate(
                after: completedAt,
                scheduleType: reminder.scheduleType,
                intervalValue: reminder.intervalValue,
                preservingTimeFrom: reminder.dueAt
            )
            if let nextDueAt {
                reminder.dueAt = nextDueAt
                reminder.isEnabled = true
            } else {
                reminder.isEnabled = false
            }

            let completionRecord = HealthRecord(
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
            cloudReminder[RecordSchema.bodyData] = try encoder.encode(reminder) as CKRecordValue
            cloudReminder[RecordSchema.updatedAt] = completedAt as CKRecordValue

            let healthID = Self.healthRecordID(for: completionRecord.id, zoneID: location.zoneID)
            let health = CKRecord(recordType: RecordSchema.healthRecord, recordID: healthID)
            health.parent = CKRecord.Reference(
                recordID: Self.rootRecordID(for: petID, zoneID: location.zoneID),
                action: .none
            )
            health[RecordSchema.entityID] = completionRecord.id.uuidString as CKRecordValue
            health[RecordSchema.petID] = petID.uuidString as CKRecordValue
            health[RecordSchema.bodyData] = try encoder.encode(completionRecord) as CKRecordValue
            health[RecordSchema.updatedAt] = completedAt as CKRecordValue

            do {
                let result = try await database.modifyRecords(
                    saving: [cloudReminder, health],
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: true
                )
                try Self.validateSaveResult(result.saveResults, recordID: cloudID)
                try Self.validateSaveResult(result.saveResults, recordID: healthID)
                return FamilyReminderCompletion(
                    reminder: reminder,
                    record: completionRecord,
                    nextDueAt: nextDueAt
                )
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
        throw FamilySharingError.editConflict
    }

    func uploadReminderCompletion(
        reminder desiredReminder: ReminderItem,
        replacing baseReminder: ReminderItem,
        record completionRecord: HealthRecord,
        location: FamilyShareLocation
    ) async throws {
        let database = database(for: location.databaseScope)
        let reminderID = Self.reminderID(for: desiredReminder.id, zoneID: location.zoneID)
        let healthID = Self.healthRecordID(for: completionRecord.id, zoneID: location.zoneID)

        for attempt in 0 ..< 2 {
            if try await existingRecord(id: healthID, in: database) != nil {
                return
            }
            guard let cloudReminder = try await existingRecord(id: reminderID, in: database),
                  let data = cloudReminder[RecordSchema.bodyData] as? Data else {
                throw FamilySharingError.sharedReminderNotFound
            }
            let serverReminder = try decoder.decode(ReminderItem.self, from: data)
            guard serverReminder.petID == desiredReminder.petID else {
                throw FamilySharingError.invalidPayload
            }

            // Someone else already completed the cycle while this device was
            // offline. Their single completion wins; the next refresh removes
            // this device's optimistic duplicate record.
            if serverReminder.lastCompletedAt != baseReminder.lastCompletedAt {
                return
            }

            let mergedReminder = Self.mergingReminderChange(
                server: serverReminder,
                desired: desiredReminder,
                base: baseReminder
            )
            cloudReminder[RecordSchema.bodyData] = try encoder.encode(mergedReminder) as CKRecordValue
            cloudReminder[RecordSchema.updatedAt] = completionRecord.occurredAt as CKRecordValue

            let healthBody = HealthRecord(
                id: completionRecord.id,
                petID: completionRecord.petID,
                kind: completionRecord.kind,
                title: completionRecord.title,
                occurredAt: completionRecord.occurredAt,
                providerName: completionRecord.providerName,
                costCents: completionRecord.costCents,
                currencyCode: completionRecord.currencyCode,
                timeZoneIdentifier: completionRecord.timeZoneIdentifier,
                notes: completionRecord.notes,
                attachments: []
            )
            let cloudHealth = CKRecord(recordType: RecordSchema.healthRecord, recordID: healthID)
            cloudHealth.parent = CKRecord.Reference(
                recordID: Self.rootRecordID(for: completionRecord.petID, zoneID: location.zoneID),
                action: .none
            )
            cloudHealth[RecordSchema.entityID] = completionRecord.id.uuidString as CKRecordValue
            cloudHealth[RecordSchema.petID] = completionRecord.petID.uuidString as CKRecordValue
            cloudHealth[RecordSchema.bodyData] = try encoder.encode(healthBody) as CKRecordValue
            cloudHealth[RecordSchema.updatedAt] = completionRecord.occurredAt as CKRecordValue

            do {
                let result = try await database.modifyRecords(
                    saving: [cloudReminder, cloudHealth],
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: true
                )
                try Self.validateSaveResult(result.saveResults, recordID: reminderID)
                try Self.validateSaveResult(result.saveResults, recordID: healthID)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
        throw FamilySharingError.editConflict
    }

    private func seedMissingStructuredRecords(
        payload: FamilyPetSharePayload,
        zoneID: CKRecordZone.ID
    ) async throws {
        let existing = try await fetchAllRecords(
            zoneID: zoneID,
            in: privateDatabase,
            desiredKeys: RecordSchema.metadataKeys
        )
        var saving: [CKRecord] = []
        var temporaryURLs: [URL] = []
        defer { removeTemporaryFiles(temporaryURLs) }
        let rootID = Self.rootRecordID(for: payload.pet.id, zoneID: zoneID)

        if let root = existing[rootID] {
            let url = try makeTemporaryFile(data: encoder.encode(payload.pet), extension: "json")
            temporaryURLs.append(url)
            root[RecordSchema.petAsset] = CKAsset(fileURL: url)
            root[RecordSchema.schemaVersion] = FamilyPetSharePayload.currentSchemaVersion as CKRecordValue
            root[RecordSchema.updatedAt] = Date() as CKRecordValue
            saving.append(root)
        }

        for record in payload.records {
            let id = Self.healthRecordID(for: record.id, zoneID: zoneID)
            if existing[id] == nil {
                let body = HealthRecord(
                    id: record.id,
                    petID: record.petID,
                    kind: record.kind,
                    title: record.title,
                    occurredAt: record.occurredAt,
                    providerName: record.providerName,
                    costCents: record.costCents,
                    currencyCode: record.currencyCode,
                    timeZoneIdentifier: record.timeZoneIdentifier,
                    notes: record.notes,
                    attachments: []
                )
                let cloudRecord = CKRecord(recordType: RecordSchema.healthRecord, recordID: id)
                cloudRecord.parent = CKRecord.Reference(recordID: rootID, action: .none)
                cloudRecord[RecordSchema.entityID] = record.id.uuidString as CKRecordValue
                cloudRecord[RecordSchema.petID] = record.petID.uuidString as CKRecordValue
                cloudRecord[RecordSchema.bodyData] = try encoder.encode(body) as CKRecordValue
                cloudRecord[RecordSchema.updatedAt] = Date() as CKRecordValue
                saving.append(cloudRecord)
            }
            for attachment in record.attachments {
                let attachmentID = Self.attachmentID(for: attachment.id, zoneID: zoneID)
                guard existing[attachmentID] == nil else { continue }
                let child = CKRecord(recordType: RecordSchema.attachment, recordID: attachmentID)
                child.parent = CKRecord.Reference(recordID: id, action: .none)
                child[RecordSchema.entityID] = attachment.id.uuidString as CKRecordValue
                child[RecordSchema.healthRecordID] = record.id.uuidString as CKRecordValue
                child[RecordSchema.attachmentKind] = attachment.kind.rawValue as CKRecordValue
                child[RecordSchema.originalName] = attachment.originalName as CKRecordValue
                child[RecordSchema.createdAt] = attachment.createdAt as CKRecordValue
                child[RecordSchema.updatedAt] = Date() as CKRecordValue
                let url = try makeTemporaryFile(
                    data: attachment.data,
                    extension: attachment.kind == .pdf ? "pdf" : "jpg"
                )
                temporaryURLs.append(url)
                child[RecordSchema.attachmentAsset] = CKAsset(fileURL: url)
                saving.append(child)
            }
        }

        for reminder in payload.reminders {
            let id = Self.reminderID(for: reminder.id, zoneID: zoneID)
            guard existing[id] == nil else { continue }
            let cloudReminder = CKRecord(recordType: RecordSchema.reminder, recordID: id)
            cloudReminder.parent = CKRecord.Reference(recordID: rootID, action: .none)
            cloudReminder[RecordSchema.entityID] = reminder.id.uuidString as CKRecordValue
            cloudReminder[RecordSchema.petID] = reminder.petID.uuidString as CKRecordValue
            cloudReminder[RecordSchema.bodyData] = try encoder.encode(reminder) as CKRecordValue
            cloudReminder[RecordSchema.updatedAt] = Date() as CKRecordValue
            saving.append(cloudReminder)
        }

        for chunk in saving.chunked(maxCount: 100) {
            try await saveRecords(chunk, deleting: [], in: privateDatabase, retryingConflicts: true)
        }
    }

    private func fetchPet(
        zoneID: CKRecordZone.ID,
        databaseScope: FamilyShareDatabaseScope
    ) async throws -> FamilySharedPet? {
        let database = database(for: databaseScope)
        let records = try await fetchAllRecords(zoneID: zoneID, in: database)
        guard let root = records.values.first(where: { $0.recordType == RecordSchema.petSnapshot }) else {
            return nil
        }

        let legacyPayload = try decodeLegacyPayload(from: root)
        let pet: Pet
        if let asset = root[RecordSchema.petAsset] as? CKAsset,
           let url = asset.fileURL {
            pet = try decodeAsset(Pet.self, from: url)
        } else if let legacyPayload {
            pet = legacyPayload.pet
        } else {
            throw FamilySharingError.invalidPayload
        }

        var healthRecords: [UUID: HealthRecord] = [:]
        var reminders: [ReminderItem] = []
        let structuredHealth = records.values.filter { $0.recordType == RecordSchema.healthRecord }
        let structuredReminders = records.values.filter { $0.recordType == RecordSchema.reminder }

        if let legacyPayload {
            healthRecords = Dictionary(uniqueKeysWithValues: legacyPayload.records.map { ($0.id, $0) })
        }
        for cloudRecord in structuredHealth {
            guard let data = cloudRecord[RecordSchema.bodyData] as? Data else { continue }
            let record = try decoder.decode(HealthRecord.self, from: data)
            healthRecords[record.id] = record
        }
        if !structuredHealth.isEmpty {
            let structuredHealthIDs = Set(structuredHealth.compactMap { cloudRecord -> UUID? in
                guard let rawID = cloudRecord[RecordSchema.entityID] as? String else { return nil }
                return UUID(uuidString: rawID)
            })
            healthRecords = healthRecords.filter { structuredHealthIDs.contains($0.key) }
            for attachmentRecord in records.values where attachmentRecord.recordType == RecordSchema.attachment {
                guard let rawRecordID = attachmentRecord[RecordSchema.healthRecordID] as? String,
                      let healthID = UUID(uuidString: rawRecordID),
                      var health = healthRecords[healthID],
                      let rawAttachmentID = attachmentRecord[RecordSchema.entityID] as? String,
                      let attachmentID = UUID(uuidString: rawAttachmentID),
                      let asset = attachmentRecord[RecordSchema.attachmentAsset] as? CKAsset,
                      let url = asset.fileURL else { continue }
                let kind = (attachmentRecord[RecordSchema.attachmentKind] as? String)
                    .flatMap(HealthRecordAttachmentKind.init(rawValue:)) ?? .image
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let attachment = HealthRecordAttachment(
                    id: attachmentID,
                    kind: kind,
                    data: data,
                    originalName: attachmentRecord[RecordSchema.originalName] as? String,
                    createdAt: attachmentRecord[RecordSchema.createdAt] as? Date ?? Date()
                )
                health.attachments.removeAll { $0.id == attachment.id }
                health.attachments.append(attachment)
                health.attachments.sort { $0.createdAt < $1.createdAt }
                healthRecords[healthID] = health
            }
        }

        if !structuredReminders.isEmpty {
            reminders = try structuredReminders.compactMap { record in
                guard let data = record[RecordSchema.bodyData] as? Data else { return nil }
                return try decoder.decode(ReminderItem.self, from: data)
            }
        } else if let legacyPayload {
            reminders = legacyPayload.reminders
        }

        let (role, ownerName, members) = try await accessDetails(
            root: root,
            sharedZoneID: zoneID,
            database: database,
            scope: databaseScope
        )
        let payload = FamilyPetSharePayload(
            pet: pet,
            records: healthRecords.values.sorted { $0.occurredAt > $1.occurredAt },
            reminders: reminders.sorted { $0.dueAt < $1.dueAt }
        )
        try payload.validate()
        return FamilySharedPet(
            location: FamilyShareLocation(
                zoneName: zoneID.zoneName,
                zoneOwnerName: zoneID.ownerName,
                databaseScope: databaseScope
            ),
            ownerName: ownerName,
            role: role,
            payload: payload,
            members: members
        )
    }

    private func decodeHealthRecord(
        id: UUID,
        zoneID: CKRecordZone.ID,
        from records: [CKRecord.ID: CKRecord]
    ) throws -> HealthRecord? {
        guard let cloudRecord = records[Self.healthRecordID(for: id, zoneID: zoneID)],
              let data = cloudRecord[RecordSchema.bodyData] as? Data else {
            return nil
        }
        var record = try decoder.decode(HealthRecord.self, from: data)
        record.attachments = []
        for attachmentRecord in records.values where attachmentRecord.recordType == RecordSchema.attachment {
            guard (attachmentRecord[RecordSchema.healthRecordID] as? String) == id.uuidString,
                  let rawAttachmentID = attachmentRecord[RecordSchema.entityID] as? String,
                  let attachmentID = UUID(uuidString: rawAttachmentID),
                  let asset = attachmentRecord[RecordSchema.attachmentAsset] as? CKAsset,
                  let url = asset.fileURL else { continue }
            let kind = (attachmentRecord[RecordSchema.attachmentKind] as? String)
                .flatMap(HealthRecordAttachmentKind.init(rawValue:)) ?? .image
            record.attachments.append(HealthRecordAttachment(
                id: attachmentID,
                kind: kind,
                data: try Data(contentsOf: url, options: .mappedIfSafe),
                originalName: attachmentRecord[RecordSchema.originalName] as? String,
                createdAt: attachmentRecord[RecordSchema.createdAt] as? Date ?? Date()
            ))
        }
        record.attachments.sort { $0.createdAt < $1.createdAt }
        return record
    }

    private func accessDetails(
        root: CKRecord,
        sharedZoneID: CKRecordZone.ID,
        database: CKDatabase,
        scope: FamilyShareDatabaseScope
    ) async throws -> (FamilyAccessRole, String?, [FamilyShareMember]) {
        let referencedShareID: CKRecord.ID
        if let rootShareID = root.share?.recordID {
            referencedShareID = rootShareID
        } else if let rawPetID = root[RecordSchema.petID] as? String,
                  let petID = UUID(uuidString: rawPetID) {
            referencedShareID = Self.shareRecordID(for: petID, zoneID: sharedZoneID)
        } else {
            return (scope == .ownerPrivate ? .owner : .viewer, nil, [])
        }
        guard let share = try await existingRecord(
            id: Self.resolvedShareRecordID(
                referencedShareID: referencedShareID,
                sharedZoneID: sharedZoneID,
                databaseScope: scope
            ),
            in: database
        ) as? CKShare else {
            return (scope == .ownerPrivate ? .owner : .viewer, nil, [])
        }
        let role: FamilyAccessRole = if scope == .ownerPrivate {
            .owner
        } else {
            share.currentUserParticipant?.permission == .readWrite ? .editor : .viewer
        }
        let ownerName = share.owner.userIdentity.nameComponents.map {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
        }
        return (role, ownerName, Self.members(from: share))
    }

    private nonisolated static func members(from share: CKShare) -> [FamilyShareMember] {
        let currentParticipantID = share.currentUserParticipant?.participantID
        return share.participants.map { participant in
            let participantRole: FamilyAccessRole = if participant.role == .owner {
                .owner
            } else if participant.permission == .readWrite {
                .editor
            } else {
                .viewer
            }
            let status: FamilyMemberStatus = switch participant.acceptanceStatus {
            case .pending: .pending
            case .accepted: .accepted
            case .removed: .removed
            default: .unknown
            }
            let fallbackName = switch status {
            case .pending: "邀请待接受"
            case .removed: "已离开的家庭成员"
            case .accepted, .unknown: "家庭成员"
            }
            let formattedName = participant.userIdentity.nameComponents.map {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
            }
            let displayName = formattedName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lookupInfo = participant.userIdentity.lookupInfo
            let accountIdentifier = [
                lookupInfo?.emailAddress,
                lookupInfo?.phoneNumber,
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return FamilyShareMember(
                id: participant.participantID,
                personID: participant.userIdentity.userRecordID?.recordName ?? participant.participantID,
                displayName: displayName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName,
                accountIdentifier: accountIdentifier,
                role: participantRole,
                status: status,
                isCurrentUser: participant.participantID == currentParticipantID
            )
        }.sorted { first, second in
            if first.role == .owner { return true }
            if second.role == .owner { return false }
            if first.status != second.status { return first.status == .accepted }
            return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
        }
    }

    private func decodeLegacyPayload(from record: CKRecord) throws -> FamilyPetSharePayload? {
        guard let asset = record[RecordSchema.payloadAsset] as? CKAsset,
              let url = asset.fileURL else { return nil }
        let payload = try decodeAsset(FamilyPetSharePayload.self, from: url)
        try payload.validate()
        return payload
    }

    private func decodeAsset<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 120_000_000 else { throw FamilySharingError.payloadTooLarge }
        return try decoder.decode(type, from: data)
    }

    private func ensureZone(_ zoneID: CKRecordZone.ID) async throws {
        let existing = try await privateDatabase.recordZones(for: [zoneID])
        if case .success? = existing[zoneID] { return }
        let result = try await privateDatabase.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)],
            deleting: []
        )
        if case .failure(let error)? = result.saveResults[zoneID] { throw error }
    }

    private func database(for scope: FamilyShareDatabaseScope) -> CKDatabase {
        scope == .ownerPrivate ? privateDatabase : sharedDatabase
    }

    private func existingRecord(id: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        let results = try await database.records(for: [id])
        guard let result = results[id] else { return nil }
        switch result {
        case .success(let record): return record
        case .failure(let error as CKError)
            where error.code == .unknownItem || error.code == .zoneNotFound:
            // Every pet has a deterministic custom-zone name, but that zone is
            // created only after the owner starts sharing the pet. Looking up a
            // share for an unshared pet therefore returns zoneNotFound, which is
            // the normal "not shared" state rather than a refresh failure.
            return nil
        case .failure(let error): throw error
        }
    }

    private func fetchAllRecords(
        zoneID: CKRecordZone.ID,
        in database: CKDatabase,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> [CKRecord.ID: CKRecord] {
        var token: CKServerChangeToken?
        var records: [CKRecord.ID: CKRecord] = [:]
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: token,
                desiredKeys: desiredKeys
            )
            token = changes.changeToken
            moreComing = changes.moreComing
            for (id, result) in changes.modificationResultsByID {
                guard case .success(let modification) = result else { continue }
                records[id] = modification.record
            }
            for deletion in changes.deletions {
                records.removeValue(forKey: deletion.recordID)
            }
        }
        return records
    }

    private func hydratingAttachmentAssets(
        for healthRecordID: UUID,
        in records: [CKRecord.ID: CKRecord],
        database: CKDatabase
    ) async throws -> [CKRecord.ID: CKRecord] {
        let attachmentIDs = Self.attachmentRecordIDs(
            for: healthRecordID,
            in: records
        )
        guard !attachmentIDs.isEmpty else { return records }

        let results = try await database.records(
            for: attachmentIDs,
            desiredKeys: RecordSchema.attachmentContentKeys
        )
        var hydrated = records
        for id in attachmentIDs {
            guard let result = results[id] else { continue }
            switch result {
            case .success(let record):
                hydrated[id] = record
            case .failure(let error as CKError)
                where error.code == .unknownItem || error.code == .zoneNotFound:
                // The attachment was deleted between the metadata scan and the
                // targeted fetch. Treat it as absent and let the retry/merge use
                // the latest remaining server attachments.
                hydrated.removeValue(forKey: id)
            case .failure(let error):
                throw error
            }
        }
        return hydrated
    }

    nonisolated static func attachmentRecordIDs(
        for healthRecordID: UUID,
        in records: [CKRecord.ID: CKRecord]
    ) -> [CKRecord.ID] {
        records.values.compactMap { record in
            guard record.recordType == RecordSchema.attachment,
                  (record[RecordSchema.healthRecordID] as? String) == healthRecordID.uuidString else {
                return nil
            }
            return record.recordID
        }
    }

    private func fetchAllZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        var token: CKServerChangeToken?
        var zoneIDs: [CKRecordZone.ID] = []
        var moreComing = true
        while moreComing {
            let changes = try await database.databaseChanges(since: token)
            token = changes.changeToken
            moreComing = changes.moreComing
            zoneIDs.append(contentsOf: changes.modifications.map(\.zoneID))
            let deleted = Set(changes.deletions.map(\.zoneID))
            zoneIDs.removeAll { deleted.contains($0) }
        }
        return Array(Set(zoneIDs))
    }

    private func saveRecords(
        _ records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        in database: CKDatabase,
        retryingConflicts: Bool
    ) async throws {
        do {
            let result = try await database.modifyRecords(
                saving: records,
                deleting: recordIDs,
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            for record in records {
                try Self.validateSaveResult(result.saveResults, recordID: record.recordID)
            }
            for recordID in recordIDs {
                if case .failure(let error)? = result.deleteResults[recordID] { throw error }
            }
        } catch let error as CKError where error.code == .serverRecordChanged && retryingConflicts {
            // Re-fetch the server versions, reapply only the fields this edit owns,
            // then save once. This keeps unrelated record edits independent.
            var merged: [CKRecord] = []
            for desired in records {
                guard let server = try await existingRecord(id: desired.recordID, in: database) else {
                    merged.append(desired)
                    continue
                }
                for key in desired.allKeys() {
                    server[key] = desired[key]
                }
                server.parent = desired.parent
                merged.append(server)
            }
            let retry = try await database.modifyRecords(
                saving: merged,
                deleting: recordIDs,
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            for record in merged {
                try Self.validateSaveResult(retry.saveResults, recordID: record.recordID)
            }
        }
    }

    private func makeTemporaryFile(data: Data, extension fileExtension: String) throws -> URL {
        guard data.count <= 120_000_000 else { throw FamilySharingError.payloadTooLarge }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZojiFamilyShare", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func removeTemporaryFiles(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private static func zoneID(for petID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "ZojiPet_\(petID.uuidString)")
    }

    /// A share reference stored on an owner's private record can retain
    /// `__defaultOwner__` after the root record is materialized in another
    /// participant's shared database. Even that root record's own ID may retain
    /// the placeholder. The zone returned by shared-database change discovery
    /// contains the real owner, so keep the record name while resolving it into
    /// that authoritative zone.
    static func resolvedShareRecordID(
        referencedShareID: CKRecord.ID,
        sharedZoneID: CKRecordZone.ID,
        databaseScope: FamilyShareDatabaseScope
    ) -> CKRecord.ID {
        guard databaseScope == .shared else { return referencedShareID }
        return CKRecord.ID(
            recordName: referencedShareID.recordName,
            zoneID: sharedZoneID
        )
    }

    private static func rootRecordID(for petID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "pet_\(petID.uuidString)", zoneID: zoneID)
    }

    private static func shareRecordID(for petID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "share_\(petID.uuidString)", zoneID: zoneID)
    }

    private static func healthRecordID(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "health_\(id.uuidString)", zoneID: zoneID)
    }

    private static func attachmentID(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "attachment_\(id.uuidString)", zoneID: zoneID)
    }

    private static func reminderID(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "reminder_\(id.uuidString)", zoneID: zoneID)
    }

    /// The owner is always present on a CKShare, even after every family member
    /// leaves. Pending invitees are also participants, so they correctly keep
    /// the share in its managed state while an invitation is awaiting acceptance.
    private static func hasInvitedParticipants(_ share: CKShare) -> Bool {
        share.participants.contains {
            $0.role != .owner && $0.acceptanceStatus != .removed
        }
    }

    private static func validateSaveResult(
        _ results: [CKRecord.ID: Result<CKRecord, Error>],
        recordID: CKRecord.ID
    ) throws {
        guard let result = results[recordID] else { throw FamilySharingError.shareCreationFailed }
        if case .failure(let error) = result { throw error }
    }
}

@MainActor
@Observable
final class FamilySharingStore {
    private static let selectedSharedPetStorageKey = "familySharing.selectedSharedPetID"

    enum SyncState: Equatable {
        case idle
        case syncing(Int)
        case pending(Int)
        case failed(Int, String)

        var message: String? {
            switch self {
            case .idle: nil
            case .syncing(let count):
                String(localized: "正在同步 \(count) 项修改…", locale: L10n.locale)
            case .pending(let count):
                String(localized: "有 \(count) 项修改等待同步", locale: L10n.locale)
            case .failed(let count, _):
                String(localized: "有 \(count) 项修改尚未同步", locale: L10n.locale)
            }
        }
    }

    var sharedPets: [FamilySharedPet] = []
    var ownedSharedPets: [FamilySharedPet] = []
    var selectedSharedPetID: String? {
        didSet {
            if let selectedSharedPetID {
                selectionDefaults.set(selectedSharedPetID, forKey: Self.selectedSharedPetStorageKey)
            } else {
                selectionDefaults.removeObject(forKey: Self.selectedSharedPetStorageKey)
            }
        }
    }
    var isRefreshing = false
    var statusMessage: String?
    var syncState: SyncState = .idle
    var recentActivities: [FamilyShareActivity] = []
    @ObservationIgnored private let selectionDefaults: UserDefaults
    @ObservationIgnored private let networkMonitor: NWPathMonitor
    @ObservationIgnored private let networkMonitorQueue: DispatchQueue
    @ObservationIgnored private var didAutoSelectLaunchCache = false
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var ownedShareMigrationTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        restoredSharedPets: [FamilySharedPet]? = nil,
        selectionDefaults: UserDefaults = .standard
    ) {
        self.selectionDefaults = selectionDefaults
        networkMonitor = NWPathMonitor()
        networkMonitorQueue = DispatchQueue(label: "com.haoqianglyu.zoji.family-network")
        let cachedPets = restoredSharedPets ?? FamilySharingLocalStore.cachedSharedPetsForLaunch()
        sharedPets = cachedPets.sorted {
            $0.pet.name.localizedStandardCompare($1.pet.name) == .orderedAscending
        }

        let persistedSelection = selectionDefaults.string(forKey: Self.selectedSharedPetStorageKey)
        if let persistedSelection,
           sharedPets.contains(where: { $0.id == persistedSelection }) {
            selectedSharedPetID = persistedSelection
        } else {
            selectedSharedPetID = sharedPets.first?.id
            didAutoSelectLaunchCache = selectedSharedPetID != nil
        }

        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                self?.retrySync()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    deinit {
        networkMonitor.cancel()
    }

    var selectedSharedPet: FamilySharedPet? {
        sharedPets.first { $0.id == selectedSharedPetID }
    }

    var pendingActivity: FamilyShareActivity? {
        recentActivities.first { !$0.isAcknowledged }
    }

    func selectPrivatePet() {
        selectedSharedPetID = nil
    }

    /// The launch cache is selected immediately for an invitee-only device.
    /// Once local pets are known, an owner's device falls back to its private
    /// pet unless the user explicitly selected a shared pet last time.
    func resolveLaunchSelection(hasPrivatePets: Bool) {
        guard didAutoSelectLaunchCache else { return }
        didAutoSelectLaunchCache = false
        if hasPrivatePets {
            selectPrivatePet()
        } else if let selectedSharedPetID {
            selectionDefaults.set(selectedSharedPetID, forKey: Self.selectedSharedPetStorageKey)
        }
    }

    func refresh(privatePayloads: [FamilyPetSharePayload]) async {
        // App Store screenshot fixtures are intentionally in-memory and must not
        // be replaced by the developer account's live CloudKit state.
        guard !PersistenceController.isMarketingDemo else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(privatePayloads: privatePayloads)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh(privatePayloads: [FamilyPetSharePayload]) async {
        guard PersistenceController.isCloudKitConfigured else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if sharedPets.isEmpty,
           let cached = try? await FamilySharingLocalStore.shared.cachedSharedPets(),
           !cached.isEmpty {
            sharedPets = sorted(cached)
        }
        async let receivedResult = asyncResult {
            try await FamilySharingService.shared.fetchSharedPets()
        }
        async let ownedResult = asyncResult {
            try await FamilySharingService.shared.fetchOwnedSharedPets(
                petNames: Dictionary(uniqueKeysWithValues: privatePayloads.map { ($0.pet.id, $0.pet.name) })
            )
        }
        let (receivedOutcome, ownedOutcome) = await (receivedResult, ownedResult)

        var refreshErrors: [String] = []
        switch receivedOutcome {
        case .success(let received):
            sharedPets = await mergeRemotePetsWithPendingChanges(received)
            try? await FamilySharingLocalStore.shared.cache(sharedPets)
            if let selectedSharedPetID,
               !sharedPets.contains(where: { $0.id == selectedSharedPetID }) {
                self.selectedSharedPetID = nil
            }
            if privatePayloads.isEmpty, selectedSharedPetID == nil {
                selectedSharedPetID = sharedPets.first?.id
            }
        case .failure(let error):
            refreshErrors.append(L10n.usesEnglish
                ? "Failed to load family-shared pets: \(error.localizedDescription)"
                : "读取家人分享失败：\(error.localizedDescription)")
        }

        switch ownedOutcome {
        case .success(let owned):
            ownedSharedPets = await mergeRemotePetsWithPendingChanges(owned)
            await reloadFamilyActivities(deliveringNotifications: true)
            // Legacy snapshot migration is maintenance work. It must not block
            // the visible sharing-state check with another full CloudKit pass.
            ownedShareMigrationTask?.cancel()
            ownedShareMigrationTask = Task {
                await FamilySharingService.shared.refreshOwnedShares(payloads: privatePayloads)
            }
        case .failure(let error):
            refreshErrors.append(L10n.usesEnglish
                ? "Failed to load data you shared: \(error.localizedDescription)"
                : "读取我分享的数据失败：\(error.localizedDescription)")
        }

        statusMessage = refreshErrors.isEmpty
            ? (sharedPets.isEmpty
                ? L10n.string("目前没有家人分享给你的宠物档案。")
                : (L10n.usesEnglish
                    ? "Synced \(sharedPets.count) family-shared pet profiles."
                    : "已同步 \(sharedPets.count) 份家人共享档案。"))
            : refreshErrors.joined(separator: "；")
        startSync()
    }

    func updatePermission(
        for member: FamilyShareMember,
        in sharedPet: FamilySharedPet,
        to role: FamilyAccessRole
    ) async throws {
        guard sharedPet.role == .owner else { throw FamilySharingError.ownerOnly }
        let updated = try await FamilySharingService.shared.updateMemberPermission(
            petID: sharedPet.pet.id,
            participantID: member.id,
            role: role
        )
        replace(updated)
        _ = try? await FamilySharingLocalStore.shared.reconcileMembers(
            petID: updated.pet.id,
            petName: updated.pet.name,
            members: updated.caregivers,
            recordChanges: false
        )
        statusMessage = String(localized: "已将\(member.displayName)设为“\(role.displayName)”。", locale: L10n.locale)
    }

    func remove(_ member: FamilyShareMember, from sharedPet: FamilySharedPet) async throws {
        guard sharedPet.role == .owner else { throw FamilySharingError.ownerOnly }
        let updated = try await FamilySharingService.shared.removeMember(
            petID: sharedPet.pet.id,
            participantID: member.id
        )
        replace(updated)
        _ = try? await FamilySharingLocalStore.shared.reconcileMembers(
            petID: updated.pet.id,
            petName: updated.pet.name,
            members: updated.caregivers,
            recordChanges: false
        )
        statusMessage = String(localized: "已撤销\(member.displayName)对“\(sharedPet.pet.name)”的访问。", locale: L10n.locale)
    }

    func acknowledgeActivities() async {
        try? await FamilySharingLocalStore.shared.acknowledgeActivities()
        recentActivities = (try? await FamilySharingLocalStore.shared.recentActivities()) ?? []
    }

    private func reloadFamilyActivities(deliveringNotifications: Bool) async {
        recentActivities = (try? await FamilySharingLocalStore.shared.recentActivities()) ?? []
        guard deliveringNotifications else { return }
        let events = (try? await FamilySharingLocalStore.shared.consumeUndeliveredActivities()) ?? []
        guard !events.isEmpty else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = L10n.string("家庭共享动态")
            content.body = event.message
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "family-activity-\(event.id.uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func refresh(_ sharedPet: FamilySharedPet) async throws {
        guard let updated = try await FamilySharingService.shared.fetchPet(location: sharedPet.location) else {
            throw FamilySharingError.sharedPetNotFound
        }
        let merged = await mergeRemotePetsWithPendingChanges([updated]).first ?? updated
        replace(merged)
        if merged.location.databaseScope == .shared {
            try? await FamilySharingLocalStore.shared.cache(sharedPets)
        }
    }

    func updatePet(_ pet: Pet, in sharedPet: FamilySharedPet) async throws {
        var updated = try liveEditablePet(sharedPet)
        let basePet = updated.payload.pet
        updated.payload.pet = pet
        try await applyOptimistic(
            updated,
            change: .save(pet, replacing: basePet, at: updated.location)
        )
    }

    func addWeightEntry(
        petID: UUID,
        kilograms: Double,
        measuredAt: Date,
        in sharedPet: FamilySharedPet
    ) async throws {
        guard sharedPet.pet.id == petID else { throw WeightEntryValidationError.petNotFound }
        try validateWeightEntry(kilograms: kilograms, measuredAt: measuredAt)

        let livePet = try liveEditablePet(sharedPet)
        var pet = livePet.pet
        var entries = pet.weightEntries ?? []
        entries.append(WeightEntry(measuredAt: measuredAt, kilograms: kilograms))
        pet.weightEntries = entries.sorted { $0.measuredAt < $1.measuredAt }
        pet.weightKilograms = pet.sortedWeightEntries.last?.kilograms
        try await updatePet(pet, in: livePet)
    }

    func updateWeightEntry(
        petID: UUID,
        entryID: UUID,
        kilograms: Double,
        measuredAt: Date,
        in sharedPet: FamilySharedPet
    ) async throws {
        guard sharedPet.pet.id == petID else { throw WeightEntryValidationError.petNotFound }
        try validateWeightEntry(kilograms: kilograms, measuredAt: measuredAt)

        let livePet = try liveEditablePet(sharedPet)
        var pet = livePet.pet
        guard var entries = pet.weightEntries,
              let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            throw WeightEntryValidationError.entryNotFound
        }
        entries[entryIndex].kilograms = kilograms
        entries[entryIndex].measuredAt = measuredAt
        pet.weightEntries = entries.sorted { $0.measuredAt < $1.measuredAt }
        pet.weightKilograms = pet.sortedWeightEntries.last?.kilograms
        try await updatePet(pet, in: livePet)
    }

    func deleteWeightEntry(
        petID: UUID,
        entryID: UUID,
        in sharedPet: FamilySharedPet
    ) async throws {
        guard sharedPet.pet.id == petID else { throw WeightEntryValidationError.petNotFound }

        let livePet = try liveEditablePet(sharedPet)
        var pet = livePet.pet
        guard pet.weightEntries?.contains(where: { $0.id == entryID }) == true else {
            throw WeightEntryValidationError.entryNotFound
        }
        pet.weightEntries?.removeAll { $0.id == entryID }
        pet.weightKilograms = pet.sortedWeightEntries.last?.kilograms
        try await updatePet(pet, in: livePet)
    }

    func saveHealthRecord(_ record: HealthRecord, in sharedPet: FamilySharedPet) async throws {
        var updated = try liveEditablePet(sharedPet)
        let baseRecord = updated.records.first { $0.id == record.id }
        updated.payload.records.removeAll { $0.id == record.id }
        updated.payload.records.append(record)
        try await applyOptimistic(
            updated,
            change: .save(record, replacing: baseRecord, at: updated.location)
        )
    }

    func deleteHealthRecord(_ record: HealthRecord, in sharedPet: FamilySharedPet) async throws {
        var updated = try liveEditablePet(sharedPet)
        let linkedReminders = updated.reminders.filter { $0.sourceRecordID == record.id }
        updated.payload.records.removeAll { $0.id == record.id }
        updated.payload.reminders.removeAll { $0.sourceRecordID == record.id }
        try await applyOptimistic(updated, change: .delete(record, at: updated.location))
        for reminder in linkedReminders {
            try await enqueue(.delete(reminder, at: updated.location))
        }
    }

    func saveReminder(_ reminder: ReminderItem, in sharedPet: FamilySharedPet) async throws {
        var updated = try liveEditablePet(sharedPet)
        let baseReminder = updated.reminders.first { $0.id == reminder.id }
        updated.payload.reminders.removeAll { $0.id == reminder.id }
        updated.payload.reminders.append(reminder)
        try await applyOptimistic(
            updated,
            change: .save(reminder, replacing: baseReminder, at: updated.location)
        )
    }

    func deleteReminder(_ reminder: ReminderItem, in sharedPet: FamilySharedPet) async throws {
        var updated = try liveEditablePet(sharedPet)
        updated.payload.reminders.removeAll { $0.id == reminder.id }
        try await applyOptimistic(updated, change: .delete(reminder, at: updated.location))
    }

    func completeReminder(_ reminder: ReminderItem, in sharedPet: FamilySharedPet) async throws -> Date? {
        var updated = try liveEditablePet(sharedPet)
        guard let baseReminder = updated.reminders.first(where: { $0.id == reminder.id }) else {
            throw FamilySharingError.sharedReminderNotFound
        }
        guard !baseReminder.isCompletionLocked() else {
            throw ReminderCompletionError.currentCycleAlreadyCompleted
        }

        let completedAt = Date()
        var completedReminder = baseReminder
        completedReminder.lastCompletedAt = completedAt
        let nextDueAt = ReminderCalculator.nextDueDate(
            after: completedAt,
            scheduleType: completedReminder.scheduleType,
            intervalValue: completedReminder.intervalValue,
            preservingTimeFrom: completedReminder.dueAt
        )
        if let nextDueAt {
            completedReminder.dueAt = nextDueAt
            completedReminder.isEnabled = true
        } else {
            completedReminder.isEnabled = false
        }
        let completionRecord = HealthRecord(
            id: UUID(),
            petID: completedReminder.petID,
            kind: completedReminder.kind,
            title: completedReminder.title,
            occurredAt: completedAt,
            providerName: nil,
            costCents: nil,
            notes: HealthRecord.reminderCompletionNoteMarker,
            attachments: []
        )
        updated.payload.reminders.removeAll { $0.id == completedReminder.id }
        updated.payload.reminders.append(completedReminder)
        updated.payload.records.append(completionRecord)
        try await applyOptimistic(
            updated,
            change: .complete(
                completedReminder,
                replacing: baseReminder,
                record: completionRecord,
                at: updated.location
            )
        )
        return nextDueAt
    }

    func leave(_ sharedPet: FamilySharedPet) async throws {
        try await FamilySharingService.shared.leaveShare(
            petID: sharedPet.pet.id,
            location: sharedPet.location
        )
        sharedPets.removeAll { $0.id == sharedPet.id }
        try? await FamilySharingLocalStore.shared.removeCachedPet(id: sharedPet.id)
        if selectedSharedPetID == sharedPet.id {
            selectedSharedPetID = nil
        }
        statusMessage = String(localized: "已退出“\(sharedPet.pet.name)”的家庭共享。", locale: L10n.locale)
    }

    func enqueueOwned(_ change: FamilyPendingChange) async {
        do {
            try await enqueue(change)
        } catch {
            statusMessage = String(localized: "修改已保存在本机，但无法建立同步任务：\(error.localizedDescription)", locale: L10n.locale)
        }
    }

    func startSync() {
        guard PersistenceController.isCloudKitConfigured, syncTask == nil else { return }
        syncTask = Task { [weak self] in
            await self?.runSync()
        }
    }

    func retrySync() {
        syncTask?.cancel()
        syncTask = nil
        startSync()
    }

    /// Used by an explicit user refresh so the refresh control remains visible
    /// until the persisted upload queue has actually had a chance to drain.
    func synchronizePendingChanges() async {
        syncTask?.cancel()
        syncTask = nil
        await runSync()
    }

    private func applyOptimistic(_ pet: FamilySharedPet, change: FamilyPendingChange) async throws {
        // Persist the outbox first. If this fails, leave the visible/cache state
        // untouched so an edit can never appear saved without a retry path.
        try await FamilySharingLocalStore.shared.enqueue(change)
        replace(pet)
        if pet.location.databaseScope == .shared {
            try? await FamilySharingLocalStore.shared.upsertCachedPet(pet)
        }
        let count = (try? await FamilySharingLocalStore.shared.pendingCount()) ?? 1
        syncState = .pending(count)
        NotificationCenter.default.post(
            name: FamilySharingService.pendingChangesDidUpdateNotification,
            object: nil
        )
        startSync()
    }

    private func enqueue(_ change: FamilyPendingChange) async throws {
        try await FamilySharingLocalStore.shared.enqueue(change)
        let count = (try? await FamilySharingLocalStore.shared.pendingCount()) ?? 1
        syncState = .pending(count)
        NotificationCenter.default.post(name: FamilySharingService.pendingChangesDidUpdateNotification, object: nil)
        startSync()
    }

    private func runSync() async {
        defer { syncTask = nil }
        let count = (try? await FamilySharingLocalStore.shared.pendingCount()) ?? 0
        guard count > 0 else {
            syncState = .idle
            return
        }
        syncState = .syncing(count)
        let result = await FamilySharingUploadCoordinator.shared.synchronize()
        if !result.recoveries.isEmpty {
            await applySyncRecoveries(result.recoveries)
        }
        if result.remainingCount == 0 {
            syncState = .idle
        } else if let error = result.errorDescription {
            syncState = .failed(result.remainingCount, error)
        } else {
            syncState = .pending(result.remainingCount)
        }
    }

    private func applySyncRecoveries(_ recoveries: [FamilySyncRecovery]) async {
        var unavailableNames: [String] = []
        var readOnlyNames: [String] = []

        for recovery in recoveries {
            let location = recovery.location
            let existing = sharedPets.first { $0.location == location }
            let petName = existing?.pet.name ?? (L10n.usesEnglish ? "a pet" : "一只宠物")

            switch recovery {
            case .shareUnavailable:
                unavailableNames.append(petName)
                sharedPets.removeAll { $0.location == location }
                if selectedSharedPetID == existing?.id {
                    selectedSharedPetID = nil
                }

            case .writePermissionRevoked:
                readOnlyNames.append(petName)
                if let serverPet = try? await FamilySharingService.shared.fetchPet(location: location) {
                    replace(serverPet)
                    try? await FamilySharingLocalStore.shared.upsertCachedPet(serverPet)
                } else {
                    sharedPets.removeAll { $0.location == location }
                    if selectedSharedPetID == existing?.id {
                        selectedSharedPetID = nil
                    }
                    if let existing {
                        try? await FamilySharingLocalStore.shared.removeCachedPet(id: existing.id)
                    }
                }
            }
        }

        var messages: [String] = []
        if !unavailableNames.isEmpty {
            let names = unavailableNames.joined(separator: L10n.usesEnglish ? ", " : "、")
            messages.append(L10n.usesEnglish
                ? "Sharing for “\(names)” stopped. Unsynced changes were removed from the upload queue."
                : "“\(names)”的共享已停止，未上传的修改已从同步队列移除")
        }
        if !readOnlyNames.isEmpty {
            let names = readOnlyNames.joined(separator: L10n.usesEnglish ? ", " : "、")
            messages.append(L10n.usesEnglish
                ? "“\(names)” is now view-only. Unsynced changes can no longer be submitted."
                : "“\(names)”已变为仅查看，未上传的修改无法提交")
        }
        statusMessage = messages.joined(separator: L10n.usesEnglish ? "; " : "；")
    }

    private func liveEditablePet(_ fallback: FamilySharedPet) throws -> FamilySharedPet {
        let candidates = fallback.location.databaseScope == .shared ? sharedPets : ownedSharedPets
        guard let livePet = candidates.first(where: {
            $0.location.zoneName == fallback.location.zoneName &&
                $0.location.zoneOwnerName == fallback.location.zoneOwnerName &&
                $0.location.databaseScope == fallback.location.databaseScope
        }) else {
            throw FamilySharingError.sharedPetNotFound
        }
        guard livePet.canEdit else { throw FamilySharingError.readOnly }
        return livePet
    }

    private func validateWeightEntry(kilograms: Double, measuredAt: Date) throws {
        guard kilograms > 0, kilograms <= 200 else {
            throw WeightEntryValidationError.weightOutOfRange
        }
        guard measuredAt <= Date() else {
            throw WeightEntryValidationError.dateInFuture
        }
    }

    private func mergeRemotePetsWithPendingChanges(_ remote: [FamilySharedPet]) async -> [FamilySharedPet] {
        guard let pending = try? await FamilySharingLocalStore.shared.allPendingChanges() else {
            return sorted(remote)
        }
        var values = remote
        for change in pending {
            guard let index = values.firstIndex(where: {
                $0.location.zoneName == change.location.zoneName &&
                    $0.location.zoneOwnerName == change.location.zoneOwnerName
            }) else { continue }
            switch change.kind {
            case .savePet:
                if let pet = change.pet {
                    values[index].payload.pet = FamilySharingService.mergingPetChange(
                        server: values[index].payload.pet,
                        desired: pet,
                        base: change.basePet
                    )
                }
            case .deletePet:
                values.remove(at: index)
            case .saveHealthRecord:
                if let record = change.healthRecord {
                    if let server = values[index].payload.records.first(where: { $0.id == record.id }) {
                        let merged = FamilySharingService.mergingHealthRecordChange(
                            server: server,
                            desired: record,
                            base: change.baseHealthRecord
                        )
                        values[index].payload.records.removeAll { $0.id == record.id }
                        values[index].payload.records.append(merged)
                    } else {
                        values[index].payload.records.append(record)
                    }
                }
            case .deleteHealthRecord:
                values[index].payload.records.removeAll { $0.id == change.entityID }
            case .saveReminder:
                if let reminder = change.reminder {
                    if let server = values[index].payload.reminders.first(where: { $0.id == reminder.id }) {
                        let merged = FamilySharingService.mergingReminderChange(
                            server: server,
                            desired: reminder,
                            base: change.baseReminder
                        )
                        values[index].payload.reminders.removeAll { $0.id == reminder.id }
                        values[index].payload.reminders.append(merged)
                    } else {
                        values[index].payload.reminders.append(reminder)
                    }
                }
            case .deleteReminder:
                values[index].payload.reminders.removeAll { $0.id == change.entityID }
            case .completeReminder:
                if let reminder = change.reminder {
                    values[index].payload.reminders.removeAll { $0.id == reminder.id }
                    values[index].payload.reminders.append(reminder)
                }
                if let record = change.healthRecord,
                   !values[index].payload.records.contains(where: { $0.id == record.id }) {
                    values[index].payload.records.append(record)
                }
            }
        }
        return sorted(values)
    }

    private func sorted(_ pets: [FamilySharedPet]) -> [FamilySharedPet] {
        pets.sorted { $0.pet.name.localizedStandardCompare($1.pet.name) == .orderedAscending }
    }

    private func asyncResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func replace(_ sharedPet: FamilySharedPet) {
        if sharedPet.location.databaseScope == .shared {
            sharedPets.removeAll { $0.id == sharedPet.id }
            sharedPets.append(sharedPet)
            sharedPets.sort { $0.pet.name.localizedStandardCompare($1.pet.name) == .orderedAscending }
        } else {
            ownedSharedPets.removeAll { $0.pet.id == sharedPet.pet.id }
            ownedSharedPets.append(sharedPet)
        }
    }
}

enum FamilySharingError: LocalizedError, Equatable {
    case unsupportedVersion
    case invalidPayload
    case payloadTooLarge
    case shareCreationFailed
    case acceptanceFailed
    case sharedPetNotFound
    case sharedReminderNotFound
    case readOnly
    case editConflict
    case ownerCannotLeave
    case pendingChangesNotSynced
    case memberNotFound
    case invalidMemberOperation
    case ownerOnly

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: L10n.string("这份家庭共享数据来自不兼容的爪记版本。")
        case .invalidPayload: L10n.string("家庭共享数据不完整，无法安全读取。")
        case .payloadTooLarge: L10n.string("共享档案过大，请减少病例附件后重试。")
        case .shareCreationFailed: L10n.string("无法创建家庭邀请，请稍后再试。")
        case .acceptanceFailed: L10n.string("无法接受家庭邀请，请确认已登录 iCloud。")
        case .sharedPetNotFound: L10n.string("这份共享宠物档案已不存在或你已没有访问权限。")
        case .sharedReminderNotFound: L10n.string("这条共享提醒已被其他家庭成员删除。")
        case .readOnly: L10n.string("拥有者给你的权限是仅查看，无法修改这份档案。")
        case .editConflict: L10n.string("另一位家庭成员刚刚修改了同一条内容，请刷新后再试。")
        case .ownerCannotLeave: L10n.string("宠物拥有者不能退出自己的共享，可以在共享管理中停止共享。")
        case .pendingChangesNotSynced: L10n.string("仍有修改等待同步，请联网同步完成后再操作。")
        case .memberNotFound: L10n.string("这位共同照护者已不在当前共享中，请刷新后重试。")
        case .invalidMemberOperation: L10n.string("不能为这位成员设置该权限。")
        case .ownerOnly: L10n.string("只有宠物拥有者可以管理共同照护者和权限。")
        }
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: maxCount).map {
            Array(self[$0 ..< Swift.min($0 + maxCount, count)])
        }
    }
}
