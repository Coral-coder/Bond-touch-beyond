import CloudKit
import SwiftUI
import UIKit
import UserNotifications

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
                .onOpenURL { url in
                    if CloudRelay.code(fromURL: url) != nil { model.handleOpenURL(url) }
                    else { model.recovery.handleOpened(url) }
                }
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
/// `AppModel`. No analytics, no third-party SDKs.
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var model: AppModel?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Ask to show alert pushes (a partner's touch wakes the phone reliably as an alert);
        // register for a device token either way so CloudKit's silent push still works.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in model?.updatePushToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NetLog.shared.log(.fail, "APNs: device token registration failed", error.localizedDescription)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await model?.handleRemoteNotification()
        return .newData
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show a partner's push even while the app is foregrounded, and refresh when one arrives.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        await model?.handleRemoteNotification()
        return [.banner, .sound]
    }
}
