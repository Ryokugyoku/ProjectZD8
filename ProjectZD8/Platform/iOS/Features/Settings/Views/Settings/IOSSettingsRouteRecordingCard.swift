#if os(iOS)
import SwiftUI

/// iOS設定画面で「走行ルートを記録」の切り替えと記録の状態を描画します。
struct IOSSettingsRouteRecordingCard: View {
    /// 保存済みの設定と記録の状態です。
    let section: RouteRecordingSettingsSection
    /// 切り替えられたことを通知するクロージャです。
    let toggle: (Bool) -> Void

    /// 記録の切り替えと状態表示を持つカードを提供します。
    ///
    /// 責務: 保存済みの設定を切り替えとして描画して変更を通知し、状態表示を部品へ任せます。
    var body: some View {
        IOSSettingsCard(
            eyebrow: LocalizedStringKey(RouteRecordingSettingsSection.eyebrowKey),
            title: LocalizedStringKey(RouteRecordingSettingsSection.titleKey),
            description: LocalizedStringKey(RouteRecordingSettingsSection.descriptionKey),
            systemImage: "location.fill"
        ) {
            VStack(spacing: IOSSettingsMetrics.routeRecordingContentSpacing) {
                recordingToggle
                IOSSettingsRouteRecordingStatusNotice(section: section)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-settings-route-recording")
    }

    /// 記録のオン・オフを切り替える行です。
    private var recordingToggle: some View {
        Toggle(
            LocalizedStringKey(RouteRecordingSettingsSection.toggleKey),
            isOn: Binding(get: { section.isEnabled }, set: { toggle($0) })
        )
        .font(.system(.body, design: .rounded, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: IOSSettingsMetrics.uploadToggleMinHeight, alignment: .leading)
        .padding(.horizontal, IOSSettingsMetrics.uploadToggleHorizontalPadding)
        .background(
            Color.primary.opacity(IOSSettingsMetrics.uploadToggleFillOpacity),
            in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.uploadToggleCornerRadius, style: .continuous)
        )
        .accessibilityIdentifier("ios-settings-route-recording-toggle")
    }
}
#endif
