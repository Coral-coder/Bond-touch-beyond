import AppIntents
import Foundation

/// The widget's tap-to-send button (iOS 17+), compiled into both the app and the widget.
///
/// Sending needs the app: the bond keys, the partner's push token, iCloud and the original
/// backend's session all live there. Conforming to `LiveActivityIntent` makes iOS run
/// `perform()` in the app's process — launching it in the background if it isn't running,
/// without opening it — so the app's copy sends straight away and writes Sent / Failed back
/// for the widget. Should iOS ever run the widget's copy instead (`WIDGET_EXTENSION`), it
/// queues the send in the App Group and pings the app with a Darwin notification; the app
/// sends it as soon as it runs.
@available(iOS 17.0, *)
struct SendMeaningIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Send a meaning"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Meaning")
    var meaningID: String

    @Parameter(title: "Partner")
    var bondID: String

    init() {}

    init(meaningID: String, bondID: String) {
        self.meaningID = meaningID
        self.bondID = bondID
    }

    func perform() async throws -> some IntentResult {
        let request = WidgetSendRequest(meaningID: meaningID, bondID: bondID, at: Date())
        #if WIDGET_EXTENSION
        WidgetShared.enqueue(request)
        WidgetShared.reloadWidget()
        #else
        await AppModel.runWidgetSend(request)
        #endif
        return .result()
    }
}
