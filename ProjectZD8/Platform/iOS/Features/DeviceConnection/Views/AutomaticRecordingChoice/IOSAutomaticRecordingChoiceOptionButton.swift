#if os(iOS)
import SwiftUI

/// 記録開始方法の選択画面で選択肢1件を説明付きのボタンとして描画します。
struct IOSAutomaticRecordingChoiceOptionButton: View {
    /// ボタンが表す選択肢です。
    let choice: AutomaticRecordingChoice
    /// ボタンが押されたことを通知するクロージャです。
    let select: () -> Void

    /// 選択肢の名称と動作の説明を持つボタンを提供します。
    ///
    /// 責務: 1件の選択肢をアイコン、名称、説明を並べた押しやすい操作として描画します。
    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: choice.systemImageName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(
                        width: IOSAutomaticRecordingChoiceMetrics.optionIconSize,
                        height: IOSAutomaticRecordingChoiceMetrics.optionIconSize
                    )
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(choice.titleKey))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(LocalizedStringKey(choice.descriptionKey))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(IOSAutomaticRecordingChoiceMetrics.optionPadding)
            .frame(maxWidth: .infinity, minHeight: IOSAutomaticRecordingChoiceMetrics.optionMinHeight, alignment: .leading)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: IOSAutomaticRecordingChoiceMetrics.optionCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IOSAutomaticRecordingChoiceMetrics.optionCornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ios-automatic-recording-choice-\(choice.rawValue)")
    }
}
#endif
