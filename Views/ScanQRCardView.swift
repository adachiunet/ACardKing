import SwiftUI
import VisionKit

/// Live QR-code scan, for the case where the *other* person already has a digital business
/// card (their own QR code, printed or shown on their phone) — reading it directly gives exact
/// field values with no OCR guessing involved at all, unlike photographing a printed card.
/// Everything here is on-device: `DataScannerViewController` is Apple's local camera+Vision
/// pipeline, and the decoded text is parsed locally by `VCardParser` — nothing is looked up or
/// sent anywhere.
struct ScanQRCardView: View {
    private enum Stage {
        case scanning
        case unsupported
        /// The QR code decoded fine but wasn't vCard text — still lets the user see what it
        /// said (a URL, plain text, whatever) rather than just failing silently.
        case notACard(String)
        case reviewing(ParsedCardFields)
    }

    @State private var stage: Stage = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        ? .scanning
        : .unsupported

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .scanning:
                    QRScannerView(
                        onDetect: { payload in
                            if let parsed = VCardParser.parse(payload) {
                                stage = .reviewing(parsed)
                            } else {
                                stage = .notACard(payload)
                            }
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("把對方的名片 QR Code 對準畫面")
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 24)
                    }
                case .unsupported:
                    ContentUnavailableView(
                        "這台裝置不支援即時 QR 掃描",
                        systemImage: "qrcode.viewfinder",
                        description: Text("可以改用「掃描一張名片」拍照辨識,或手動輸入。")
                    )
                case .notACard(let payload):
                    ContentUnavailableView {
                        Label("這不是名片格式的 QR Code", systemImage: "qrcode")
                    } description: {
                        Text(payload)
                            .font(.caption)
                            .lineLimit(6)
                    } actions: {
                        Button("重新掃描") { stage = .scanning }
                    }
                case .reviewing(let parsed):
                    CardFormView(
                        existingCard: nil,
                        prefilled: parsed,
                        prefilledFrontImagePath: nil,
                        prefilledBackImagePath: nil
                    )
                }
            }
            .navigationTitle("掃描 QR 名片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismissAction() }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismissAction
}

/// Thin `UIViewControllerRepresentable` wrapper around `DataScannerViewController`, configured
/// to look for QR codes only and hand back the first one it recognizes.
private struct QRScannerView: UIViewControllerRepresentable {
    var onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDetect: onDetect) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onDetect: (String) -> Void
        private var didFire = false

        init(onDetect: @escaping (String) -> Void) {
            self.onDetect = onDetect
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            // Only the first recognized QR code in a session is used — `didFire` guards against
            // the same or a second code being reported again before this view has had a chance
            // to transition away from the live camera.
            guard !didFire else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    didFire = true
                    onDetect(payload)
                    break
                }
            }
        }
    }
}
