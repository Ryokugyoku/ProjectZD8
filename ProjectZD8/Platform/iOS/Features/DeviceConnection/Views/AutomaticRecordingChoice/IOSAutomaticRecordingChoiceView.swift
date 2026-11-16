#if os(iOS)
import SwiftUI

/// 初回サインイン直後に、車両検知時の記録開始方法を選ぶiOS画面を描画します。
///
/// 選択せずに閉じる経路は持ちません。どちらかを選ぶと呼び出し元が表示済みにして閉じます。
struct IOSAutomaticRecordingChoiceView: View {
    /// 選択肢が選ばれたことを通知するクロージャです。
    let select: (AutomaticRecordingChoice) -> Void

    /// 見出し、説明、2つの選択肢を縦に並べた選択画面を提供します。
    ///
    /// 責務: 選択肢の違いを説明し、選ばれた選択肢を型付き値で通知します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSAutomaticRecordingChoiceMetrics.sectionSpacing) {
                heading
                VStack(spacing: IOSAutomaticRecordingChoiceMetrics.optionSpacing) {
                    ForEach(AutomaticRecordingChoicePromptContent.choices) { choice in
                        IOSAutomaticRecordingChoiceOptionButton(choice: choice) { select(choice) }
                    }
                }
            }
            .padding(.horizontal, IOSAutomaticRecordingChoiceMetrics.horizontalPadding)
            .padding(.top, IOSAutomaticRecordingChoiceMetrics.topPadding)
            .padding(.bottom, IOSAutomaticRecordingChoiceMetrics.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .interactiveDismissDisabled(true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-automatic-recording-choice-screen")
    }

    /// 画面の目的と後から変更できることを示す見出しです。
    private var heading: some View {
        VStack(alignment: .leading, spacing: IOSAutomaticRecordingChoiceMetrics.headingSpacing) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: IOSAutomaticRecordingChoiceMetrics.heroIconFontSize, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(
                    width: IOSAutomaticRecordingChoiceMetrics.heroIconSize,
                    height: IOSAutomaticRecordingChoiceMetrics.heroIconSize
                )
                .background(
                    Color.accentColor.opacity(IOSAutomaticRecordingChoiceMetrics.heroIconFillOpacity),
                    in: RoundedRectangle(cornerRadius: IOSAutomaticRecordingChoiceMetrics.heroIconCornerRadius, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(LocalizedStringKey(AutomaticRecordingChoicePromptContent.titleKey))
                .font(.system(.title, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(LocalizedStringKey(AutomaticRecordingChoicePromptContent.messageKey))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
