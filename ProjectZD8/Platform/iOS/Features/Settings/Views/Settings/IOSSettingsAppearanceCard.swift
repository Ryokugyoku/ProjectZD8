#if os(iOS)
import SwiftUI

/// iOS設定画面で外観モードを切り替える設定カードを描画します。
struct IOSSettingsAppearanceCard: View {
    /// 現在の外観モードです。
    let appearance: SettingsAppearance
    /// 外観モードが選ばれたことを通知するクロージャです。
    let select: (SettingsAppearance) -> Void

    /// 外観モードごとのボタンを横に並べたカードを提供します。
    ///
    /// 責務: 外観モードの一覧を選択状態付きのボタンとして並べます。
    var body: some View {
        IOSSettingsCard(
            eyebrow: "settings.appearance.eyebrow",
            title: "settings.appearance.title",
            description: "settings.appearance.description",
            systemImage: "circle.lefthalf.filled"
        ) {
            HStack(spacing: IOSSettingsMetrics.appearanceButtonSpacing) {
                ForEach(SettingsAppearance.allCases) { candidate in
                    IOSSettingsAppearanceButton(appearance: candidate, isSelected: appearance == candidate) {
                        select(candidate)
                    }
                }
            }
        }
    }
}
#endif
