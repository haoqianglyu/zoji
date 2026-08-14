import CloudKit
import UIKit

final class ZojiAppDelegate: NSObject, UIApplicationDelegate {
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
