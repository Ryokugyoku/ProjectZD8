#if os(iOS)
import SwiftUI

/// iOS設定画面で1件のアダプタースロットの役割と選択状態を行として描画します。
struct IOSSettingsAdapterRow: View {
    /// 行が表すアダプタースロットです。
    let slot: AdapterConnectionRole
    /// スロットの説明(選択済みの名前、または未選択の文言キー)です。
    let description: AdapterSlotSettingsDescription
    /// 行が押されたことを通知するクロージャです。
    let select: () -> Void

    /// 実接続を装わず選択導線を提供するアダプター行を提供します。
    ///
    /// 責務: 1件のアダプタースロットを役割と選択導線を持つ行として描画します。
    var body: some View {
        Button(action: select) {
            HStack(spacing: IOSSettingsMetrics.choiceRowSpacing) {
                icon
                VStack(alignment: .leading, spacing: IOSSettingsMetrics.adapterRowTextSpacing) {
                    titleLine
                    descriptionText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: IOSSettingsMetrics.adapterRowSpacerMinLength)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(IOSSettingsMetrics.choiceRowPadding)
            .frame(maxWidth: .infinity, minHeight: IOSSettingsMetrics.choiceRowMinHeight, alignment: .leading)
            .background(
                Color.primary.opacity(IOSSettingsMetrics.adapterRowFillOpacity),
                in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.choiceRowCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("settings.adapter.select"))
        .accessibilityIdentifier("ios-settings-adapter-\(slot.rawValue)")
    }

    /// プライマリーかどうかです。強調色の切り替えに使います。
    private var isPrimary: Bool { slot == .primary }

    /// スロットの役割を表すアイコンです。
    private var icon: some View {
        Image(systemName: slot.systemImage)
            .font(.system(size: IOSSettingsMetrics.adapterRowIconFontSize, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.accentColor : Color.secondary)
            .frame(width: IOSSettingsMetrics.cardIconSize, height: IOSSettingsMetrics.cardIconSize)
            .background(
                isPrimary
                    ? Color.accentColor.opacity(IOSSettingsMetrics.adapterRowPrimaryIconFillOpacity)
                    : Color.primary.opacity(IOSSettingsMetrics.adapterRowSecondaryFillOpacity),
                in: Circle()
            )
    }

    /// スロット名と役割バッジの行です。
    private var titleLine: some View {
        HStack(spacing: IOSSettingsMetrics.adapterRowTitleSpacing) {
            Text(slot.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))

            Text(slot.badge)
                .font(.system(size: IOSSettingsMetrics.adapterBadgeFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(isPrimary ? Color.accentColor : Color.secondary)
                .padding(.horizontal, IOSSettingsMetrics.adapterBadgeHorizontalPadding)
                .padding(.vertical, IOSSettingsMetrics.adapterBadgeVerticalPadding)
                .background(Color.primary.opacity(IOSSettingsMetrics.adapterRowSecondaryFillOpacity), in: Capsule())
        }
    }

    /// スロットの説明の文言です。アダプター名はそのまま、未選択は文言キーとして描画します。
    private var descriptionText: Text {
        switch description {
        case let .adapterName(name): Text(verbatim: name)
        case let .localizationKey(key): Text(LocalizedStringKey(key))
        }
    }
}
#endif
