import UIKit

/// Profile photos from the original backend: Firebase Storage `images/<firebaseId>/profile`
/// in the default bucket, for partners whose profile has `hasImage`, and for the user.
/// Cached on disk so they show immediately on the next launch.
extension AppModel {
    private static var photoCacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func cacheURL(_ key: String) -> URL {
        photoCacheDir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".jpg")
    }

    /// The loaded photo for a partner (by bond id). Safe to call while rendering.
    func photo(forBond bondID: String?) -> UIImage? {
        guard let bondID else { return nil }
        return partnerPhotos[bondID]
    }

    /// Shows the cached photo right away, then downloads it once per profile version.
    func loadPartnerPhoto(bondID: String, uid: String, version: Int64) {
        let key = "\(bondID)#\(version)"
        guard !uid.isEmpty, !photoRequests.contains(key) else { return }
        photoRequests.insert(key)
        if partnerPhotos[bondID] == nil,
           let cached = UIImage(contentsOfFile: Self.cacheURL("bond-" + bondID).path) {
            partnerPhotos[bondID] = cached
        }
        Task {
            guard let token = try? await legacyToken(),
                  let data = try? await FirebaseStorage.download("images/\(uid)/profile", token: token),
                  let image = UIImage(data: data) else { return }
            partnerPhotos[bondID] = image
            try? data.write(to: Self.cacheURL("bond-" + bondID), options: .atomic)
        }
    }

    /// Downloads the signed-in user's own photo, if they have one.
    func loadMyPhoto() {
        if myPhoto == nil, let cached = UIImage(contentsOfFile: Self.cacheURL("me").path) { myPhoto = cached }
        guard legacySignedIn, !photoRequests.contains("me") else { return }
        photoRequests.insert("me")
        Task {
            guard let token = try? await legacyToken(), let uid = BondBackend.tokenUID(token),
                  let data = try? await FirebaseStorage.download("images/\(uid)/profile", token: token),
                  let image = UIImage(data: data) else { return }
            myPhoto = image
            try? data.write(to: Self.cacheURL("me"), options: .atomic)
        }
    }

    /// The image to blur behind the app: the selected partner's photo when they have one
    /// and the photo background is on for them.
    var backgroundPhoto: UIImage? {
        guard let id = selectedPartnerID, store.photoBackground(for: id) else { return nil }
        return photo(forBond: id)
    }
}
