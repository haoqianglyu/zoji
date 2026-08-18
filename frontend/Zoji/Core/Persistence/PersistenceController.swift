import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.haoqianglyu.zoji"
    #if DEBUG
    nonisolated static let isMarketingDemo = ProcessInfo.processInfo.arguments.contains("-zojiMarketingDemo")
    nonisolated static let isMarketingFamilyScreenshot =
        ProcessInfo.processInfo.arguments.contains("-zojiMarketingFamilyScreenshot")
    nonisolated static let isMarketingRecordsScreenshot =
        ProcessInfo.processInfo.arguments.contains("-zojiMarketingRecordsScreenshot")
    nonisolated static let isMarketingRemindersScreenshot =
        ProcessInfo.processInfo.arguments.contains("-zojiMarketingRemindersScreenshot")
    nonisolated static let isMarketingHospitalsUSScreenshot =
        ProcessInfo.processInfo.arguments.contains("-zojiMarketingHospitalsUSScreenshot")
    nonisolated static let isMarketingHealthRecordScreenshot =
        ProcessInfo.processInfo.arguments.contains("-zojiMarketingHealthRecordScreenshot")
    #else
    nonisolated static let isMarketingDemo = false
    nonisolated static let isMarketingFamilyScreenshot = false
    nonisolated static let isMarketingRecordsScreenshot = false
    nonisolated static let isMarketingRemindersScreenshot = false
    nonisolated static let isMarketingHospitalsUSScreenshot = false
    nonisolated static let isMarketingHealthRecordScreenshot = false
    #endif
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
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = (inMemory || Self.isMarketingDemo)
            ? .none
            : .private(Self.cloudKitContainerIdentifier)
        #else
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            // Store App Store screenshot fixtures only in memory so they can
            // never enter a developer's real CloudKit container.
            isStoredInMemoryOnly: inMemory || Self.isMarketingDemo,
            cloudKitDatabase: cloudKitDatabase
        )

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            usesCloudKit = !inMemory && !Self.isMarketingDemo && Self.isCloudKitConfigured
            startupMessage = nil
        } catch {
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory || Self.isMarketingDemo,
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
