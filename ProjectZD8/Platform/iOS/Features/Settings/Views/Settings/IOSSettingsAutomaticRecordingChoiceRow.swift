#if os(iOS)
import SwiftUI

/// iOS設定画面で記録開始方法の選択肢1件を選択状態付きの行として描画します。
struct IOSSettingsAutomaticRecordingChoiceRow: View {
    /// 行が表す選択肢です。
    let choice: AutomaticRecordingChoice
    /// 保存済みの選択と一致するかどうかです。
    let isSelected: Bool
    /// 行が選ばれたことを通知するクロージャです。
    let select: () -> Void

    /// 選択肢の名称、説明、選択状態を持つ行を提供します。
    ///
    /// 責務: 1件の選択肢を、色以外の手掛かりでも選択状態が分かる操作として描画します。
    var body: some View {
        Button(action: select) {
            HStack(spacing: IOSSettingsMetrics.choiceRowSpacing) {
                Image(systemName: choice.systemImageName)
                    .font(.system(size: IOSSettingsMetrics.choiceRowIconFontSize, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: IOSSettingsMetrics.cardIconSize, height: IOSSettingsMetrics.cardIconSize)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(IOSSettingsMetrics.choiceRowSelectedIconFillOpacity)
                            : Color.primary.opacity(IOSSettingsMetrics.choiceRowUnselectedIconFillOpacity),
                        in: Circle()
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: IOSSettingsMetrics.choiceRowTextSpacing) {
                    Text(LocalizedStringKey(choice.titleKey))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(LocalizedStringKey(choice.descriptionKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: IOSSettingsMetrics.choiceRowSpacerMinLength)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(IOSSettingsMetrics.choiceRowPadding)
            .frame(maxWidth: .infinity, minHeight: IOSSettingsMetrics.choiceRowMinHeight, alignment: .leading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(IOSSettingsMetrics.choiceRowSelectedFillOpacity)
                    : Color.primary.opacity(IOSSettingsMetrics.choiceRowUnselectedFillOpacity),
                in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.choiceRowCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ios-settings-automatic-recording-\(choice.rawValue)")
    }
}
#endif
