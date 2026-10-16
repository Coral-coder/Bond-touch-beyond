import CloudKit
import SwiftUI
import UIKit

/// Invites a partner into the bond's shared zone with the system share sheet.
///
/// The share is already saved to the server (its URL is populated) before we get here, and
/// `UICloudSharingController` is *presented* modally by a real host controller — embedding
/// it directly as a SwiftUI sheet, or handing it an unsaved share via a preparation handler,
/// is what left the sheet grey or spinning in Messages.
struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    /// Called with a message when the invite can't be offered (e.g. not signed in).
    var onError: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(share: share, container: container, dismiss: { dismiss() }, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = HostController()
        host.coordinator = context.coordinator
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    /// Presents the sharing controller once on screen; when it reappears (the controller was
    /// dismissed), it closes the SwiftUI sheet.
    final class HostController: UIViewController {
        var coordinator: Coordinator?
        private var state = 0   // 0 not shown, 1 presenting, 2 done

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            switch state {
            case 0:
                state = 1
                coordinator?.present(from: self)
            case 1:
                state = 2
                coordinator?.dismiss()
            default:
                break
            }
        }
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let share: CKShare
        let container: CKContainer
        let dismiss: () -> Void
        let onError: ((String) -> Void)?

        init(share: CKShare, container: CKContainer, dismiss: @escaping () -> Void,
             onError: ((String) -> Void)?) {
            self.share = share
            self.container = container
            self.dismiss = dismiss
            self.onError = onError
        }

        func present(from host: UIViewController) {
            container.accountStatus { [weak self] status, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard status == .available else {
                        NetLog.shared.log(.fail, "iCloud invite unavailable", "account status \(status.rawValue)")
                        self.onError?("Sign in to iCloud (Settings → your name → iCloud) to invite a partner.")
                        self.dismiss()
                        return
                    }
                    let controller = UICloudSharingController(share: self.share, container: self.container)
                    controller.delegate = self
                    controller.availablePermissions = [.allowReadWrite, .allowPrivate]
                    controller.modalPresentationStyle = .formSheet
                    host.present(controller, animated: true)
                }
            }
        }

        // MARK: UICloudSharingControllerDelegate

        func itemTitle(for csc: UICloudSharingController) -> String? { "Bond Touch Beyond" }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            NetLog.shared.log(.fail, "iCloud invite failed", error.localizedDescription)
            onError?("Couldn't send the invite: \(error.localizedDescription)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            NetLog.shared.log(.ok, "iCloud invite sent")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
