#if os(iOS)
import SwiftUI

/// iOS設定画面で「エンジン停止とみなす時間」を選ぶカードを描画します。
struct IOSSettingsVehicleOffCard: View {
    /// 現在の選択と表示する選択肢です。
    let section: VehicleOffDetectionSettingsSection
    /// 選択肢が選ばれたことを通知するクロージャです。
    let select: (VehicleOffDetectionDelay) -> Void

    /// 時間の選択肢を持つカードを提供します。
    ///
    /// 責務: 保存済みの時間を選択状態として示し、選ばれた時間を型付き値で通知します。
    var body: some View {
        IOSSettingsCard(
            eyebrow: LocalizedStringKey(VehicleOffDetectionSettingsSection.eyebrowKey),
            title: LocalizedStringKey(VehicleOffDetectionSettingsSection.titleKey),
            description: LocalizedStringKey(VehicleOffDetectionSettingsSection.descriptionKey),
            systemImage: "engine.combustion"
        ) {
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
            .accessibilityIdentifier("ios-settings-vehicle-off-delay")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-settings-vehicle-off")
    }
}
#endif
