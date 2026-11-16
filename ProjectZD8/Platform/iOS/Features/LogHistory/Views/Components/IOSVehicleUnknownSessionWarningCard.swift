#if os(iOS)
import SwiftUI

/// iOSのホームと車両画面で、車両を特定できなかったログがあることと紐付けへの導線を描画します。
struct IOSVehicleUnknownSessionWarningCard: View {
    /// 表示する警告です。
    let warning: VehicleUnknownSessionWarning
    /// 主要操作が選ばれたことを通知するクロージャです。
    let send: (VehicleUnknownSessionWarningPrimaryAction) -> Void

    /// 警告の見出し、件数の分かる本文、主要操作を提供します。
    ///
    /// 責務: 警告の内容を描画し、選ばれた主要操作を型付き値で通知します。非表示の警告では何も描画しません。
    var body: some View {
        if let titleKey = warning.titleKey {
            VStack(alignment: .leading, spacing: IOSVehicleUnknownSessionMetrics.spacing) {
                Label(LocalizedStringKey(titleKey), systemImage: "questionmark.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = IOSVehicleUnknownSessionWarningMessageFormatter.message(for: warning) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let action = warning.primaryAction {
                    actionButton(action)
                }
            }
            .padding(IOSVehicleUnknownSessionMetrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: IOSVehicleUnknownSessionMetrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IOSVehicleUnknownSessionMetrics.cornerRadius, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ios-vehicle-unknown-session-warning")
        }
    }

    /// 主要操作のボタンを生成します。
    ///
    /// 責務: 1件の主要操作をボタンとして描画し、押されたら通知します。
    /// - Parameter action: ボタンが表す主要操作。
    /// - Returns: 主要操作を通知するボタン。
    private func actionButton(_ action: VehicleUnknownSessionWarningPrimaryAction) -> some View {
        Button {
            send(action)
        } label: {
            Label(LocalizedStringKey(action.titleKey), systemImage: action.systemImageName)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: IOSVehicleUnknownSessionMetrics.actionMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("ios-vehicle-unknown-session-warning-action")
    }
}
#endif
