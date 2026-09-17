import SwiftUI

/// A single image with pinch-to-zoom and drag-to-pan, plus double-tap to zoom in/reset.
/// Used inside `PhotoViewerView` so a scanned card's printed text is actually legible enough
/// to proofread against the form fields — the small inline thumbnails elsewhere in the app
/// (list row, header avatar, "名片照片" section) are sized for recognition, not for checking
/// whether OCR or manual entry got a digit or a character wrong.
struct ZoomableImageView: View {
    let image: UIImage

    @State private var currentZoom: CGFloat = 1.0
    @State private var totalZoom: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var totalOffset: CGSize = .zero

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 6.0
    private let doubleTapZoom: CGFloat = 2.5

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(totalZoom * currentZoom)
                .offset(x: totalOffset.width + currentOffset.width, y: totalOffset.height + currentOffset.height)
                .gesture(magnificationGesture(in: geometry.size))
                .simultaneousGesture(dragGesture(in: geometry.size))
                .onTapGesture(count: 2) { toggleZoom() }
                .accessibilityLabel("名片照片,雙指縮放或雙點放大")
        }
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                currentZoom = value
            }
            .onEnded { value in
                totalZoom = min(max(totalZoom * value, minZoom), maxZoom)
                currentZoom = 1.0
                clampOffset(in: size)
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        // Only pans once zoomed in — at 1x the image already fits the frame exactly, so a
        // drag there is more useful left free for a parent TabView's page-swipe gesture
        // (front/back) than captured here for a pan that wouldn't go anywhere anyway.
        DragGesture()
            .onChanged { value in
                guard totalZoom > minZoom else { return }
                currentOffset = value.translation
            }
            .onEnded { value in
                guard totalZoom > minZoom else {
                    currentOffset = .zero
                    return
                }
                totalOffset.width += value.translation.width
                totalOffset.height += value.translation.height
                currentOffset = .zero
                clampOffset(in: size)
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if totalZoom > minZoom {
                totalZoom = minZoom
                totalOffset = .zero
            } else {
                totalZoom = doubleTapZoom
            }
            currentZoom = 1.0
            currentOffset = .zero
        }
    }

    /// Keeps the image from being panned so far that its edge leaves the visible frame —
    /// clamped against how much bigger than the frame the current zoom level actually makes it.
    /// At `minZoom` (1x, scaledToFit) this always clamps back to zero, which is what keeps a
    /// drag inert until the user has actually zoomed in past the frame's own bounds.
    private func clampOffset(in size: CGSize) {
        let maxOffsetX = max(0, (size.width * (totalZoom - 1)) / 2)
        let maxOffsetY = max(0, (size.height * (totalZoom - 1)) / 2)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            totalOffset.width = min(max(totalOffset.width, -maxOffsetX), maxOffsetX)
            totalOffset.height = min(max(totalOffset.height, -maxOffsetY), maxOffsetY)
        }
    }
}
