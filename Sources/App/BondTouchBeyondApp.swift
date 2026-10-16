import CloudKit
import SwiftUI
import UIKit

@main
struct BondTouchBeyondApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.heart)
                .environmentObject(model.recovery)
                .onOpenURL { model.recovery.handleOpened($0) }
                .task { await model.bootstrap() }
                .onAppear { appDelegate.model = model }
                .onChange(of: scenePhase) { phase in
                    // Brief `.inactive` moments (Control Centre, alerts) don't count as leaving.
                    if phase == .active { Task { await model.setActive(true) } }
                    if phase == .background { Task { await model.setActive(false) } }
                }
        }
    }
}

/// Minimal app delegate: registers for silent pushes and routes notifications into
/// `AppModel`, and installs the scene delegate that accepts CloudKit share invites. No
/// analytics, no third-party SDKs.
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

    // This app uses the SwiftUI (scene-based) lifecycle, so CloudKit share acceptance is
    // delivered to the scene delegate, NOT this app delegate's
    // userDidAcceptCloudKitShareWith. Install a scene delegate for it.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
}

/// Accepts CloudKit share invites. SwiftUI's `WindowGroup` still provides the window; this
/// only adds the share-acceptance callbacks (warm app and cold launch via the invite link).
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            AppModel.deliverShare(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        AppModel.deliverShare(cloudKitShareMetadata)
    }
}
