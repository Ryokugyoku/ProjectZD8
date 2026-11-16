#if os(iOS)
import SwiftUI

/// iOS設定画面で車両検知時の記録開始方法の選択と終了時の案内を描画します。
struct IOSSettingsAutomaticRecordingCard: View {
    /// 現在の選択と表示する選択肢です。
    let section: AutomaticRecordingSettingsSection
    /// 選択肢が選ばれたことを通知するクロージャです。
    let select: (AutomaticRecordingChoice) -> Void

    /// 記録開始方法の選択肢と終了時の案内をカードとして提供します。
    ///
    /// 責務: 保存済みの選択を選択状態として示し、選ばれた選択肢を型付き値で通知します。
    var body: some View {
        IOSSettingsCard(
            eyebrow: LocalizedStringKey(AutomaticRecordingSettingsSection.eyebrowKey),
            title: LocalizedStringKey(AutomaticRecordingSettingsSection.titleKey),
            description: LocalizedStringKey(AutomaticRecordingSettingsSection.descriptionKey),
            systemImage: "dot.radiowaves.left.and.right"
        ) {
            VStack(spacing: IOSSettingsMetrics.choiceRowListSpacing) {
                ForEach(section.choices) { choice in
                    IOSSettingsAutomaticRecordingChoiceRow(
                        choice: choice,
                        isSelected: section.isSelected(choice),
                        select: { select(choice) }
                    )
                }
                terminationNotice
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-settings-automatic-recording")
    }

    /// アプリスイッチャーで終了すると自動検知が止まることを常に示す案内です。
    private var terminationNotice: some View {
        Label(
            LocalizedStringKey(AutomaticRecordingSettingsSection.terminationNoticeKey),
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(IOSSettingsMetrics.noticePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(IOSSettingsMetrics.noticeFillOpacity),
            in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.noticeCornerRadius, style: .continuous)
        )
        .accessibilityIdentifier("ios-settings-automatic-recording-termination-notice")
    }
}
#endif
