import SwiftUI
import UIKit

/// Wraps UIActivityViewController so exported files (vCard, CSV, backup JSON) can go through
/// the system share sheet — save to Files, AirDrop, a cloud drive, whatever the user picks.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // On iPad, UIActivityViewController is presented as a popover and iOS requires a
        // source view/rect to anchor it to — without this it's a guaranteed crash the moment
        // this runs on an iPad (or an iPhone in a size class that gets treated as regular,
        // e.g. some external-display/Stage Manager setups). Anchoring to the key window's
        // center is a safe default since this sheet has no specific button rect to point at.
        if let popover = controller.popoverPresentationController,
           let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
