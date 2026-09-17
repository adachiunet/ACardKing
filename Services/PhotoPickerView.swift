import SwiftUI
import PhotosUI
import UIKit

/// Wraps `PHPickerViewController` (iOS 14+) to multi-select EXISTING photos already sitting
/// in the user's photo library — e.g. business-card photos someone sent over Messages/LINE,
/// screenshots of a card, or old camera-roll photos — as an alternative to scanning fresh
/// ones with the camera (`DocumentScannerView`). Deliberately PHPickerViewController and not
/// the older `UIImagePickerController`/`PHPhotoLibrary` APIs: it runs the picker UI in a
/// separate system process and hands this app back only the exact photos the user picked, so
/// (per Apple's docs) it does NOT require photo-library access at all — no
/// `NSPhotoLibraryUsageDescription` key, no permission prompt, nothing to configure.
struct PhotoPickerView: UIViewControllerRepresentable {
    /// Called with the loaded images, in the order the user picked them, once every picked
    /// item has finished loading. Never called with an empty array — see onCancel.
    var onPick: ([UIImage]) -> Void
    /// Called if the user dismisses the picker having picked nothing.
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0 // 0 = no limit — this is the whole point of "batch"
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        init(_ parent: PhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.onCancel()
                return
            }
            // Each result's image loads asynchronously and independently, so results are
            // written into a pre-sized, index-addressed array rather than appended — that
            // keeps the final order matching the order the user picked them in even if the
            // loads themselves finish in a different order.
            //
            // SAFETY: `itemProvider.loadObject`'s completion handler is NOT guaranteed to run
            // on the main thread (Apple's docs explicitly call this out as "an arbitrary
            // background queue"), so with `selectionLimit = 0` (batch picking, potentially
            // dozens of photos) this fires many of these completions concurrently. Writing
            // directly into a shared `[UIImage?]` from those concurrent callbacks is a data
            // race — Swift arrays give no thread-safety guarantee for concurrent mutation, and
            // this can trap under exclusivity checking or silently corrupt/drop entries in
            // Release. Every write (and the paired `group.leave()`) is funneled through the
            // main queue below so the array only ever changes from one thread at a time.
            var images = [UIImage?](repeating: nil, count: results.count)
            let group = DispatchGroup()
            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage {
                            images[index] = image
                        }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                self.parent.onPick(images.compactMap { $0 })
            }
        }
    }
}
