import CloudKit
import SwiftUI
import UIKit

/// Wraps `UICloudSharingController` to invite a partner into the bond's shared zone.
///
/// The share is created and saved **inside the preparation handler** and handed back once
/// saved, so the controller passes the system share sheet a `CKShare` whose server URL is
/// populated. Passing a pre-built, unsaved share makes the invite-link preview spin forever.
struct CloudShareSheet: UIViewControllerRepresentable {
    let root: CKRecord
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            let share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = "Bond Touch Beyond" as CKRecordValue
            share.publicPermission = .none

            var savedShare = share
            let op = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: nil)
            op.perRecordSaveBlock = { recordID, result in
                if recordID == share.recordID, case .success(let record) = result,
                   let s = record as? CKShare {
                    savedShare = s
                }
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: completion(savedShare, container, nil)
                case .failure(let error): completion(nil, nil, error)
                }
            }
            container.privateCloudDatabase.add(op)
        }
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
