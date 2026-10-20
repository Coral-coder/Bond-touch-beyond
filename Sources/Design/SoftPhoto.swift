import CoreImage
import SwiftUI
import UIKit

/// A photo filling the view, softly blurred. The blur is worked out once, off the main
/// thread, at the size it's shown, and kept — a live `.blur` re-blurs the whole screen every
/// time anything above it moves (the bubbles and raindrops, scrolling), which made screens lag.
struct SoftPhoto: View {
    let photo: UIImage
    /// Blur radius in points (0 = sharp).
    let softness: Double
    @State private var shown: UIImage?

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: shown ?? photo).resizable().scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                // Live blur only for the moment before the kept one is ready.
                .blur(radius: shown == nil ? softness : 0, opaque: true)
                .scaleEffect(1.08)
                .clipped()
                .task(id: Key(photo: ObjectIdentifier(photo), softness: Int(softness.rounded()),
                              width: Int(geo.size.width), height: Int(geo.size.height))) {
                    let size = geo.size
                    let radius = softness
                    let image = photo
                    let blurred = await Task.detached(priority: .userInitiated) {
                        SoftPhotoRenderer.render(image, radius: radius, fill: size)
                    }.value
                    if !Task.isCancelled, let blurred { shown = blurred }
                }
        }
    }

    private struct Key: Equatable {
        let photo: ObjectIdentifier
        let softness: Int
        let width: Int
        let height: Int
    }
}

/// The blurring itself, kept apart from the view so it can run off the main thread.
enum SoftPhotoRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let cache = NSCache<NSString, UIImage>()

    /// The photo scaled down to cover `fill` (at 1 pixel per point — it's blurred anyway) and
    /// blurred by `radius` points.
    static func render(_ photo: UIImage, radius: Double, fill: CGSize) -> UIImage? {
        guard fill.width > 0, fill.height > 0, let cg = photo.cgImage else { return nil }
        let key = "\(ObjectIdentifier(photo).hashValue)-\(Int(radius.rounded()))-\(Int(fill.width))x\(Int(fill.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let source = CIImage(cgImage: cg).oriented(CGImagePropertyOrientation(photo.imageOrientation))
        let scale = max(fill.width / source.extent.width, fill.height / source.extent.height)
        var image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        if radius >= 0.5 {
            image = image.clampedToExtent().applyingGaussianBlur(sigma: radius / 2).cropped(to: extent)
        }
        guard let out = context.createCGImage(image, from: extent) else { return nil }
        let result = UIImage(cgImage: out)
        cache.setObject(result, forKey: key)
        return result
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
