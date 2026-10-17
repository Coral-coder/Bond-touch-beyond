import CloudKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct BondTouchBeyondApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// The app's model is owned by the app delegate, not a view: iOS can launch the app in
    /// the background for a partner's push (or a bracelet event) without ever showing a
    /// screen, and the touch must still reach the bracelet.
    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.heart)
                .environmentObject(model.recovery)
                .onOpenURL { url in
                    // A meaning tapped on the widget (iOS 16; iOS 17 sends without opening the app).
                    if let request = WidgetShared.sendRequest(from: url) { Task { await model.sendFromWidget(request) } }
                    else if CloudRelay.code(fromURL: url) != nil { model.handleOpenURL(url) }
                    else { model.recovery.handleOpened(url) }
                }
                .task { await model.bootstrap() }
                .onChange(of: scenePhase) { phase in
                    // Brief `.inactive` moments (Control Centre, alerts) don't count as leaving.
                    if phase == .active { Task { await model.setActive(true) } }
                    if phase == .background { Task { await model.setActive(false) } }
                }
        }
    }
}

/// Owns the app model and routes pushes into it — also when iOS launches the app in the
/// background with no UI. No analytics, no third-party SDKs.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Ask to show alert pushes (a partner's touch wakes the phone reliably as an alert);
        // register for a device token either way so pushes reach the app.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        // Start up straight away, even with no screen (a background launch for a push or a
        // bracelet event), so iCloud, the bracelet and the original backend are ready.
        Task { await model.bootstrap() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        model.updatePushToken(hex)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NetLog.shared.log(.fail, "APNs: device token registration failed", error.localizedDescription)
    }

    /// A partner's push, in the foreground or background (or after a background launch):
    /// play the touch it carries on the bracelet, sync, and only report done once the
    /// bracelet has the whole touch — iOS may suspend the app as soon as this returns.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let task = application.beginBackgroundTask(withName: "partner-push")
        defer { application.endBackgroundTask(task) }
        await model.handleRemoteNotification(userInfo)
        return .newData
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// With the app open, a partner's push is handled at once and shows silently — the
    /// bracelet (or the phone's own vibration, if it isn't connected) already plays the touch.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        await MainActor.run { Task { await self.model.handleRemoteNotification(info) } }
        return [.banner, .list]
    }
}
