import SwiftUI
import UIKit

extension Color {
    /// Parses a "#RRGGBB" (or "RRGGBB") hex string. Falls back to a neutral gray on bad input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b: UInt64
        if cleaned.count == 6 {
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        } else {
            r = 128; g = 128; b = 128
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }

    /// Converts back to a "#RRGGBB" string, used when saving a color picked via ColorPicker.
    func toHex() -> String? {
        let uiColor = UIColor(self)
        guard let components = uiColor.cgColor.components, components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// A small default palette new tags cycle through, so tags are visually distinguishable
    /// without asking the user to pick a color every time.
    static let tagPalette: [String] = [
        "#4A90D9", "#50C878", "#E67E22", "#E74C3C",
        "#9B59B6", "#1ABC9C", "#F1C40F", "#34495E"
    ]
}
