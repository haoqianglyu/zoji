import CloudKit
import UIKit
import UserNotifications

struct ReminderNotificationRoute: Equatable, Sendable {
    let deliveryID = UUID()
    let reminderID: UUID
    let petID: UUID
}

@MainActor
enum ReminderNotificationRouter {
    static let didOpenNotification = Notification.Name("ZojiDidOpenReminderNotification")
    private(set) static var pendingRoute: ReminderNotificationRoute?

    static func publish(userInfo: [AnyHashable: Any]) {
        guard let reminderValue = userInfo["reminderID"] as? String,
              let reminderID = UUID(uuidString: reminderValue),
              let petValue = userInfo["petID"] as? String,
              let petID = UUID(uuidString: petValue) else { return }
        let route = ReminderNotificationRoute(reminderID: reminderID, petID: petID)
        pendingRoute = route
        NotificationCenter.default.post(name: didOpenNotification, object: route)
    }

    static func clear(_ route: ReminderNotificationRoute) {
        if pendingRoute == route { pendingRoute = nil }
    }
}

final class ZojiAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            ReminderNotificationRouter.publish(
                userInfo: response.notification.request.content.userInfo
            )
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = ZojiSceneDelegate.self
        return configuration
    }
}

final class ZojiSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        accept(metadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task {
            await MainActor.run {
                FamilyShareAcceptanceState.shared.begin(metadata: metadata)
            }
            do {
                try await FamilySharingService.shared.accept(metadata: metadata)
                await MainActor.run {
                    FamilyShareAcceptanceState.shared.beginLoading()
                    NotificationCenter.default.post(
                        name: FamilySharingService.didAcceptShareNotification,
                        object: nil
                    )
                }
            } catch {
                await MainActor.run {
                    FamilyShareAcceptanceState.shared.fail(error.localizedDescription)
                    NotificationCenter.default.post(
                        name: FamilySharingService.didAcceptShareNotification,
                        object: nil,
                        userInfo: ["error": error]
                    )
                }
            }
        }
    }
}
