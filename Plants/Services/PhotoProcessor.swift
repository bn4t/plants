import UIKit

enum PhotoProcessor {
    /// Downscale longest side to 1024px and JPEG-compress at 0.7.
    static func process(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // point-based size should equal pixels so the cap is really 1024px
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: 0.7)
    }
}
