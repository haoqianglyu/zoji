import SwiftData
import SwiftUI

@main
struct ZojiApp: App {
    @UIApplicationDelegateAdaptor(ZojiAppDelegate.self) private var appDelegate
    private let persistenceController: PersistenceController
    @State private var store: AppStore
    @State private var familyStore = FamilySharingStore()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @AppStorage(AppColorTheme.storageKey) private var colorTheme = AppColorTheme.warm

    init() {
        let persistenceController = PersistenceController.shared
        self.persistenceController = persistenceController
        _store = State(initialValue: AppStore.live(
            petRepository: SwiftDataPetRepository(modelContainer: persistenceController.container),
            healthRecordRepository: SwiftDataHealthRecordRepository(modelContainer: persistenceController.container),
            reminderRepository: SwiftDataReminderRepository(modelContainer: persistenceController.container),
            notificationScheduler: LocalReminderNotificationScheduler()
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .environment(familyStore)
                .environment(\.locale, L10n.locale)
                .tint(colorTheme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(persistenceController.container)
    }
}
