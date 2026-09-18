import SwiftUI
import UIKit

/// AcardKing 的品牌色票與版面基礎值 — 延續 App 圖示既有的「深藍 + 金色」商務調性，讓名片列表、
/// 詳細頁、表單等每個畫面共用同一套色彩/圓角/間距，而不是各自散落的字面值(`.blue`、寫死的
/// padding 數字…)。所有顏色都用 `UIColor { traits in … }` 依 Light/Dark 動態提供兩種色階，不是
/// 寫死單一顏色——深色模式下同一個「品牌色」需要提亮才維持得住對比,直接共用亮色模式的數值會
/// 糊在底色裡。
enum Theme {
    /// App 圖示底色的深藍 — 當作全 App 的主色（導覽列、主要按鈕、選取狀態、連結色）。整個 App
    /// 只在 `CardKingApp` 的根視圖套一次 `.tint(Theme.navy)`，SwiftUI 會把它往下帶到每個畫面的
    /// 按鈕/Toggle/Picker,不需要每個畫面各自設定。
    static let navy = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.60, blue: 0.85, alpha: 1)
            : UIColor(red: 0.09, green: 0.16, blue: 0.35, alpha: 1)
    })

    /// App 圖示皇冠的金色 — 當強調色用（我的最愛星號、重點徽章），刻意只用在小面積、需要「這裡
    /// 比較重要」的地方，不是拿來大面積鋪色，商務調性才不會變成花俏配色。
    static let gold = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.85, green: 0.70, blue: 0.35, alpha: 1)
            : UIColor(red: 0.72, green: 0.56, blue: 0.20, alpha: 1)
    })

    /// 卡片背景 — 跟系統的分組列表底色刻意區分開，讓名片列表裡每一列讀起來像一張獨立的卡片，
    /// 而不是系統預設 List 那種列與列之間只靠一條分隔線區分的清單感。
    static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.secondarySystemGroupedBackground : UIColor.white
    })

    /// 卡片外框 — 極細、低對比,只在需要跟背景切開時才看得出來,不是視覺上的主角。
    static let cardBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.separator : UIColor(white: 0.85, alpha: 1)
    })

    /// 列表整體的底色 — 比卡片背景稍暗一階，卡片才會有「浮在上面」的層次感（純白卡片放在純白
    /// 背景上會糊成一片，看不出分隔）。
    static let listBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.systemGroupedBackground : UIColor(white: 0.95, alpha: 1)
    })

    static let cardCornerRadius: CGFloat = 14
    static let cardSpacing: CGFloat = 10
}

extension View {
    /// 套在任何要看起來像「一張卡片」的內容外面 —白底（深色模式用次要分組色）、細邊框、圓角、
    /// 淺陰影。目前只有 `CardRow`(名片列表每一列)使用，未來其他畫面要做同樣的卡片感時共用
    /// 這個 modifier，不要各自再刻一份。
    func cardStyle() -> some View {
        self
            .padding(12)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}
