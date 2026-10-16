import CloudKit
import SwiftUI
import UIKit

/// Invites a partner into the bond's shared zone with the system share sheet.
///
/// `UICloudSharingController` must be *presented* modally by a real parent view controller;
/// embedding it directly as a SwiftUI sheet's content renders a blank grey screen. So this
/// hosts a plain container controller that presents the sharing controller once it appears,
/// and dismisses the SwiftUI sheet when it closes.
///
/// The share is created and saved **inside the preparation handler**, with the root record,
/// so the controller hands the system sheet a `CKShare` whose server URL is populated
/// (passing a pre-built, unsaved share makes the invite link preview spin forever).
struct CloudShareSheet: UIViewControllerRepresentable {
    let root: CKRecord
    let container: CKContainer
    /// Called with an error message when the invite can't be offered (e.g. not signed in).
    var onError: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(root: root, container: container, dismiss: { dismiss() }, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = HostController()
        host.coordinator = context.coordinator
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    /// Presents the sharing controller once the host is on screen; when the host reappears
    /// (the sharing controller was dismissed), it closes the SwiftUI sheet.
    final class HostController: UIViewController {
        var coordinator: Coordinator?
        private var state = 0   // 0 not shown, 1 presenting, 2 done

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            switch state {
            case 0:
                state = 1
                coordinator?.present(from: self) { [weak self] in self?.state = 2 }
            case 1:
                // The sharing controller (or the account-error alert) was dismissed.
                state = 2
                coordinator?.dismiss()
            default:
                break
            }
        }
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let root: CKRecord
        let container: CKContainer
        let dismiss: () -> Void
        let onError: ((String) -> Void)?

        init(root: CKRecord, container: CKContainer, dismiss: @escaping () -> Void,
             onError: ((String) -> Void)?) {
            self.root = root
            self.container = container
            self.dismiss = dismiss
            self.onError = onError
        }

        /// `markPresented` is called once something has actually been presented on the host
        /// (the share controller, or an error alert), so the host knows to close the sheet
        /// when it reappears.
        func present(from host: UIViewController, markPresented: @escaping () -> Void) {
            container.accountStatus { [weak self] status, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard status == .available else {
                        NetLog.shared.log(.fail, "iCloud invite unavailable", "account status \(status.rawValue)")
                        self.onError?("Sign in to iCloud (Settings → your name → iCloud) to invite a partner.")
                        self.dismiss()
                        return
                    }
                    markPresented()
                    self.showController(from: host)
                }
            }
        }

        private func showController(from host: UIViewController) {
            let controller = UICloudSharingController { [root, container] _, completion in
                let share = CKShare(rootRecord: root)
                share[CKShare.SystemFieldKey.title] = "Bond Touch Beyond" as CKRecordValue
                share.publicPermission = .none
                var savedShare = share
                let op = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: nil)
                op.perRecordSaveBlock = { recordID, result in
                    if recordID == share.recordID, case .success(let record) = result,
                       let s = record as? CKShare { savedShare = s }
                }
                op.modifyRecordsResultBlock = { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success: completion(savedShare, container, nil)
                        case .failure(let error):
                            NetLog.shared.record(.fail, "iCloud invite: share save failed", error.localizedDescription)
                            completion(nil, nil, error)
                        }
                    }
                }
                op.qualityOfService = .userInitiated
                container.privateCloudDatabase.add(op)
            }
            controller.delegate = self
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            controller.modalPresentationStyle = .formSheet
            host.present(controller, animated: true)
        }

        // MARK: UICloudSharingControllerDelegate

        func itemTitle(for csc: UICloudSharingController) -> String? { "Bond Touch Beyond" }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            NetLog.shared.log(.fail, "iCloud invite failed", error.localizedDescription)
            onError?("Couldn't create the invite: \(error.localizedDescription)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            NetLog.shared.log(.ok, "iCloud invite sent")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
