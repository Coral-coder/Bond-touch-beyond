import UIKit

/// Profile photos. The user picks their own in Settings; it is kept on this phone and sent to
/// iCloud partners inside the profile record. iCloud partners' photos arrive the same way.
/// All are cached on disk so they show immediately on the next launch.
extension AppModel {
    /// The user's own photo, as sent to partners (square JPEG).
    var myPhotoFileURL: URL? {
        FileManager.default.fileExists(atPath: Self.myPhotoURL.path) ? Self.myPhotoURL : nil
    }

    private static var myPhotoURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("me.jpg")
    }

    /// Sets the user's photo: cropped square, 640 px, and shared with every partner.
    func setMyPhoto(_ image: UIImage) {
        guard let data = Self.profileJPEG(image) else { return }
        try? data.write(to: Self.myPhotoURL, options: .atomic)
        myPhoto = UIImage(data: data)
        Task { await publishProfile() }
    }

    func removeMyPhoto() {
        try? FileManager.default.removeItem(at: Self.myPhotoURL)
        try? FileManager.default.removeItem(at: Self.cacheURL("me"))
        myPhoto = nil
        Task { await publishProfile() }
    }

    /// Centre-crops to a square and scales to 640 px, JPEG.
    static func profileJPEG(_ image: UIImage, side: CGFloat = 640) -> Data? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = side / min(w, h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - w * scale) / 2, y: (side - h * scale) / 2,
                                  width: w * scale, height: h * scale))
        }
        return out.jpegData(compressionQuality: 0.85)
    }

    /// A partner's photo arrived (iCloud): show it and cache it.
    func setPartnerPhoto(_ data: Data, bondID: String) {
        guard let image = UIImage(data: data) else { return }
        partnerPhotos[bondID] = image
        try? data.write(to: Self.cacheURL("bond-" + bondID), options: .atomic)
    }

    /// Shows a partner's cached photo, if one was saved before.
    func loadCachedPhoto(bondID: String) {
        guard partnerPhotos[bondID] == nil,
              let cached = UIImage(contentsOfFile: Self.cacheURL("bond-" + bondID).path) else { return }
        partnerPhotos[bondID] = cached
    }

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

    /// The user's own photo: the one picked here, else one cached by an earlier version.
    func loadMyPhoto() {
        if let mine = UIImage(contentsOfFile: Self.myPhotoURL.path) { myPhoto = mine; return }
        if myPhoto == nil, let cached = UIImage(contentsOfFile: Self.cacheURL("me").path) { myPhoto = cached }
    }

    /// The image to blur behind the app: the selected partner's photo when they have one
    /// and the photo background is on for them.
    var backgroundPhoto: UIImage? {
        guard let id = selectedPartnerID, store.photoBackground(for: id) else { return nil }
        return photo(forBond: id)
    }
}
