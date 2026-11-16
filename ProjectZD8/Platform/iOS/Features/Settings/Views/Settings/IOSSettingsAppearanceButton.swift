#if os(iOS)
import SwiftUI

/// iOS設定画面で1件の外観モードを選ぶボタンを描画します。
struct IOSSettingsAppearanceButton: View {
    /// ボタンが表す外観モードです。
    let appearance: SettingsAppearance
    /// 現在選択されている外観モードかどうかです。
    let isSelected: Bool
    /// ボタンが押されたことを通知するクロージャです。
    let select: () -> Void

    /// 選択状態を複数の視覚手掛かりで示すボタンを提供します。
    ///
    /// 責務: 1件の外観モードを選択状態が分かる操作として描画します。
    var body: some View {
        Button(action: select) {
            VStack(spacing: IOSSettingsMetrics.appearanceButtonContentSpacing) {
                Image(systemName: appearance.systemImage)
                    .font(.system(size: IOSSettingsMetrics.appearanceIconFontSize, weight: .semibold))

                Text(appearance.title)
                    .font(.system(size: IOSSettingsMetrics.appearanceTitleFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(IOSSettingsMetrics.appearanceTitleMinimumScaleFactor)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(IOSSettingsMetrics.appearanceUnselectedForegroundOpacity))
            .frame(maxWidth: .infinity, minHeight: IOSSettingsMetrics.appearanceButtonMinHeight)
            .background(
                isSelected ? Color.accentColor : Color.primary.opacity(IOSSettingsMetrics.appearanceUnselectedFillOpacity),
                in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.appearanceButtonCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IOSSettingsMetrics.appearanceButtonCornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ios-settings-appearance-\(appearance.rawValue)")
    }

    /// 選択状態に応じた枠線の色です。
    private var strokeColor: Color {
        isSelected
            ? Color.white.opacity(IOSSettingsMetrics.appearanceSelectedStrokeOpacity)
            : Color.primary.opacity(IOSSettingsMetrics.appearanceUnselectedStrokeOpacity)
    }
}
#endif
