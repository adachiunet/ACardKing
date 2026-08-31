import SwiftUI
import VisionKit
import UIKit

/// SwiftUI wrapper around Apple's system document-scanner camera (VNDocumentCameraViewController).
/// The system UI itself supports capturing multiple pages in one session (tap the shutter
/// repeatedly, then "Save") — this is what powers both the single-card flow (front + back,
/// captured as two separate sessions) and the batch-scan flow (many card fronts captured
/// as multiple pages in one session).
///
/// Note: per Apple's documentation, this system view controller does not require adding
/// NSCameraUsageDescription to Info.plist, since it runs out-of-process. SETUP.md still
/// recommends adding the key defensively, since this hasn't been verified on a real device.
struct DocumentScannerView: UIViewControllerRepresentable {
    /// Called with every page captured in this session, in capture order.
    var onScan: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                parent.onCancel()
                return
            }
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: pageIndex))
            }
            parent.onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            print("DocumentScannerView scan error: \(error)")
            parent.onCancel()
        }
    }
}
