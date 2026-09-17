import SwiftUI

/// One labeled photo to show in `PhotoViewerView` — e.g. ("正面", frontImage). `Identifiable`
/// via a fresh UUID (not the underlying file's name) since the same on-disk photo can
/// legitimately appear more than once across the "更早的照片" history.
struct ViewablePhoto: Identifiable {
    let id = UUID()
    let label: String
    let image: UIImage
}

/// Bundles a `PhotoViewerView`'s photo set with which page to open on, so a caller can drive
/// `.fullScreenCover(item:)` from one `@State` value instead of two separate ones (a `Bool`
/// flag plus the photos/index) that SwiftUI could otherwise present a beat out of sync with
/// each other — see the callers in CardDetailView/CardFormView.
struct PhotoViewerRequest: Identifiable {
    let id = UUID()
    let photos: [ViewablePhoto]
    let initialIndex: Int

    init(photos: [ViewablePhoto], startAt index: Int = 0) {
        self.photos = photos
        self.initialIndex = index
    }
}

/// Full-screen, swipeable (when there's more than one photo), pinch-to-zoom photo viewer.
/// The point: CardDetailView/CardFormView's inline thumbnails are sized for quick recognition,
/// not for proofreading — this is what actually lets the user hold a scanned card's photo up
/// against the typed-out fields and see whether OCR (or their own typing) got something wrong.
/// Presented via `.fullScreenCover(item:)` from both screens.
struct PhotoViewerView: View {
    let photos: [ViewablePhoto]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(photos: [ViewablePhoto], initialIndex: Int = 0) {
        self.photos = photos
        self.initialIndex = photos.indices.contains(initialIndex) ? initialIndex : 0
        _currentIndex = State(initialValue: self.initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    ZoomableImageView(image: photo.image)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
                if photos.indices.contains(currentIndex), photos.count > 1 || !photos[currentIndex].label.isEmpty {
                    Text(photos[currentIndex].label)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, photos.count > 1 ? 36 : 16)
                }
            }
        }
        .statusBarHidden()
    }
}
