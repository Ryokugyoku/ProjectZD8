#if os(macOS)
import SwiftUI

/// macOS設定画面で「エンジン停止とみなす時間」を選ぶカードを描画します。
struct MacOSSettingsVehicleOffCard: View {
    /// 現在の選択と表示する選択肢です。
    let section: VehicleOffDetectionSettingsSection
    /// 選択肢が選ばれたことを通知するクロージャです。
    let select: (VehicleOffDetectionDelay) -> Void
    /// ウインドウ寸法に応じた拡大率を持つ寸法です。
    let metrics: MacOSAppShellMetrics

    /// 見出しと時間の選択肢を持つカードを提供します。
    ///
    /// 責務: 保存済みの時間を選択状態として示し、選ばれた時間を型付き値で通知します。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSSettingsVehicleOffMetrics.cardSpacing * metrics.scale) {
            header
            Picker(
                LocalizedStringKey(VehicleOffDetectionSettingsSection.titleKey),
                selection: Binding(get: { section.selectedDelay }, set: select)
            ) {
                ForEach(section.choices) { delay in
                    Text(LocalizedStringKey(VehicleOffDetectionSettingsSection.titleKey(for: delay))).tag(delay)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("macos-settings-vehicle-off-delay")
        }
        .padding(MacOSSettingsVehicleOffMetrics.cardPadding * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: cardShape)
        .overlay { cardShape.stroke(Color.primary.opacity(0.07), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-settings-vehicle-off")
    }

    /// カードの外形です。
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacOSSettingsVehicleOffMetrics.cardCornerRadius * metrics.scale, style: .continuous)
    }

    /// アイコンと見出し文言の並びです。
    private var header: some View {
        HStack(alignment: .top, spacing: MacOSSettingsVehicleOffMetrics.headerSpacing * metrics.scale) {
            Image(systemName: "engine.combustion")
                .font(.system(size: MacOSSettingsVehicleOffMetrics.iconFontSize * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(
                    width: MacOSSettingsVehicleOffMetrics.iconSize * metrics.scale,
                    height: MacOSSettingsVehicleOffMetrics.iconSize * metrics.scale
                )
                .background(
                    Color.accentColor.opacity(0.11),
                    in: RoundedRectangle(
                        cornerRadius: MacOSSettingsVehicleOffMetrics.iconCornerRadius * metrics.scale,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MacOSSettingsVehicleOffMetrics.textSpacing * metrics.scale) {
                Text(LocalizedStringKey(VehicleOffDetectionSettingsSection.eyebrowKey))
                    .font(.system(size: MacOSSettingsVehicleOffMetrics.eyebrowFontSize * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(MacOSSettingsVehicleOffMetrics.eyebrowTracking * metrics.scale)
                    .foregroundStyle(.tint)
                Text(LocalizedStringKey(VehicleOffDetectionSettingsSection.titleKey))
                    .font(.system(size: MacOSSettingsVehicleOffMetrics.titleFontSize * metrics.scale, weight: .bold, design: .rounded))
                Text(LocalizedStringKey(VehicleOffDetectionSettingsSection.descriptionKey))
                    .font(.system(size: MacOSSettingsVehicleOffMetrics.descriptionFontSize * metrics.scale, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
#endif
