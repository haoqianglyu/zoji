import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.haoqianglyu.zoji"
    static var isCloudKitConfigured: Bool {
        #if ICLOUD_SYNC_ENABLED
        true
        #else
        false
        #endif
    }

    let container: ModelContainer
    let usesCloudKit: Bool
    let startupMessage: String?

    private init(inMemory: Bool = false) {
        let schema = Schema([
            PetEntity.self,
            HealthRecordEntity.self,
            HealthRecordAttachmentEntity.self,
            ReminderRuleEntity.self
        ])
        #if ICLOUD_SYNC_ENABLED
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = inMemory
            ? .none
            : .private(Self.cloudKitContainerIdentifier)
        #else
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKitDatabase
        )

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            usesCloudKit = !inMemory && Self.isCloudKitConfigured
            startupMessage = nil
        } catch {
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
            do {
                container = try ModelContainer(for: schema, configurations: [localConfiguration])
                usesCloudKit = false
                startupMessage = L10n.string("iCloud 同步暂时不可用，数据仍会安全保存在本机。")
            } catch {
                fatalError("Unable to create Zoji SwiftData container: \(error)")
            }
        }
    }
}
