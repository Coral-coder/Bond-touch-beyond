import CloudKit
import SwiftUI
import UIKit

@main
struct BondTouchBeyondApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.bootstrap() }
                .onAppear { appDelegate.model = model }
        }
    }
}

/// Minimal app delegate: registers for silent pushes and routes CloudKit share
/// acceptance + notifications into `AppModel`. No analytics, no third-party SDKs.
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var model: AppModel?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await model?.handleRemoteNotification()
        return .newData
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await model?.accept(metadata) }
    }
}
