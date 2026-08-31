import SwiftUI
import UIKit

/// Single-card scan flow: capture the front, optionally capture the back, run on-device OCR
/// on the front, then hand the guessed fields + both photos to CardFormView for the user to
/// review and confirm. For scanning a whole stack of cards at once, see BatchScanView instead.
struct ScanCardView: View {
    private enum Stage {
        case scanningFront
        case scanningBack
        case processing
        case mergeReview(frontFields: ParsedCardFields, backFields: ParsedCardFields, frontPath: String?, backPath: String?)
        case reviewing(ParsedCardFields, frontPath: String?, backPath: String?)
        case failed
    }

    @State private var stage: Stage = .scanningFront
    @State private var frontImagePath: String?
    @State private var backImagePath: String?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .scanningFront:
                    DocumentScannerView(
                        onScan: { images in handleFrontScan(images) },
                        onCancel: { }
                    )
                case .scanningBack:
                    DocumentScannerView(
                        onScan: { images in handleBackScan(images) },
                        onCancel: { proceedToProcessing() }
                    )
                case .processing:
                    ProgressView("辨識文字中…")
                        .onAppear(perform: runOCR)
                case .mergeReview(let frontFields, let backFields, let front, let back):
                    FrontBackMergeReviewView(front: frontFields, back: backFields) { resolved in
                        stage = .reviewing(resolved, frontPath: front, backPath: back)
                    }
                case .reviewing(let parsed, let front, let back):
                    CardFormView(
                        existingCard: nil,
                        prefilled: parsed,
                        prefilledFrontImagePath: front,
                        prefilledBackImagePath: back
                    )
                case .failed:
                    ContentUnavailableView(
                        "辨識失敗",
                        systemImage: "exclamationmark.triangle",
                        description: Text("可以直接手動輸入資料")
                    )
                }
            }
        }
    }

    private func handleFrontScan(_ images: [UIImage]) {
        guard let image = images.first else { return }
        frontImagePath = ImageStorageService.save(image)
        stage = .scanningBack
    }

    private func handleBackScan(_ images: [UIImage]) {
        if let image = images.first {
            backImagePath = ImageStorageService.save(image)
        }
        proceedToProcessing()
    }

    private func proceedToProcessing() {
        stage = .processing
    }

    /// Runs OCR on the front photo, then — if a back photo was also captured — on the back
    /// too, and merges both guesses into one set of fields (OCRService.merge). Both photos
    /// are always kept on the saved card either way; this only affects which text fields
    /// get pre-filled.
    private func runOCR() {
        guard let frontPath = frontImagePath, let frontImage = ImageStorageService.load(frontPath) else {
            stage = .failed
            return
        }
        OCRService.recognizeText(in: frontImage) { frontLines in
            let frontParsed = OCRService.parse(lines: frontLines)

            guard let backPath = backImagePath, let backImage = ImageStorageService.load(backPath) else {
                DispatchQueue.main.async {
                    stage = .reviewing(frontParsed, frontPath: frontImagePath, backPath: backImagePath)
                }
                return
            }

            OCRService.recognizeText(in: backImage) { backLines in
                let backParsed = OCRService.parse(lines: backLines)
                DispatchQueue.main.async {
                    if OCRService.divergentFields(front: frontParsed, back: backParsed) {
                        stage = .mergeReview(
                            frontFields: frontParsed, backFields: backParsed,
                            frontPath: frontImagePath, backPath: backImagePath
                        )
                    } else {
                        let merged = OCRService.merge(front: frontParsed, back: backParsed)
                        stage = .reviewing(merged, frontPath: frontImagePath, backPath: backImagePath)
                    }
                }
            }
        }
    }
}
