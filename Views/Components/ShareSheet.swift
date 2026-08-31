import SwiftUI
import UIKit

/// Wraps UIActivityViewController so exported files (vCard, CSV, backup JSON) can go through
/// the system share sheet — save to Files, AirDrop, a cloud drive, whatever the user picks.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
