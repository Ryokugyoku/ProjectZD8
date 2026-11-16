#if os(iOS)
import SwiftUI

/// iOS設定画面でセッション終了時のiCloud自動アップロードを切り替えるカードを描画します。
struct IOSSettingsUploadCard: View {
    /// 自動アップロードが有効かどうかです。
    let isEnabled: Bool
    /// 切り替えられたことを通知するクロージャです。
    let change: (Bool) -> Void

    /// 自動アップロードの切り替えを持つカードを提供します。
    ///
    /// 責務: 現在の設定を切り替えとして描画し、変更を通知します。
    var body: some View {
        IOSSettingsCard(
            eyebrow: "settings.upload.eyebrow",
            title: "settings.upload.title",
            description: "settings.upload.description",
            systemImage: "icloud.and.arrow.up.fill"
        ) {
            Toggle(
                "settings.upload.automatic",
                isOn: Binding(
                    get: { isEnabled },
                    set: { change($0) }
                )
            )
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: IOSSettingsMetrics.uploadToggleMinHeight, alignment: .leading)
                .padding(.horizontal, IOSSettingsMetrics.uploadToggleHorizontalPadding)
                .background(
                    Color.primary.opacity(IOSSettingsMetrics.uploadToggleFillOpacity),
                    in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.uploadToggleCornerRadius, style: .continuous)
                )
        }
        .accessibilityIdentifier("ios-settings-automatic-upload")
    }
}
#endif
