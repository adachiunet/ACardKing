import UIKit
import CoreImage.CIFilterBuiltins

/// Fully on-device QR code generation (CoreImage's built-in `CIQRCodeGenerator`), used by
/// MyCardView to render the user's own card as a scannable code. No network call, no
/// third-party dependency — same offline principle as everything else in the app.
enum QRCodeService {
    /// `scale` upsizes CoreImage's native (very small, one point per module) output so the
    /// result stays crisp on screen; `.interpolation(.none)` on the `Image` that displays it
    /// keeps the module edges sharp instead of blurring them.
    static func generate(from string: String, scale: CGFloat = 10) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
