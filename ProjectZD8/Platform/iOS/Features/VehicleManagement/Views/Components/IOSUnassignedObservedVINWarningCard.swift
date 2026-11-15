#if os(iOS)
import SwiftUI

/// iOSのホームと車両画面で、未登録車両のログがあることと車両登録への導線を描画します。
struct IOSUnassignedObservedVINWarningCard: View {
    /// 表示する警告です。
    let warning: UnassignedObservedVINWarning
    /// 主要操作が選ばれたことを通知するクロージャです。
    let send: (UnassignedObservedVINWarningPrimaryAction) -> Void

    /// 警告の見出し、件数の分かる本文、主要操作を提供します。
    ///
    /// 責務: 警告の内容を描画し、選ばれた主要操作を型付き値で通知します。非表示の警告では何も描画しません。
    var body: some View {
        if let titleKey = warning.titleKey {
            VStack(alignment: .leading, spacing: IOSUnassignedObservedVINWarningMetrics.spacing) {
                Label(LocalizedStringKey(titleKey), systemImage: warning.systemImageName ?? "exclamationmark.triangle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = IOSUnassignedObservedVINWarningMessageFormatter.message(for: warning) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let action = warning.primaryAction {
                    actionButton(action)
                }
            }
            .padding(IOSUnassignedObservedVINWarningMetrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: IOSUnassignedObservedVINWarningMetrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IOSUnassignedObservedVINWarningMetrics.cornerRadius, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ios-unassigned-vin-warning")
        }
    }

    /// 主要操作のボタンを生成します。
    ///
    /// 責務: 1件の主要操作をシアンのボタンとして描画し、押されたら通知します。
    /// - Parameter action: ボタンが表す主要操作。
    /// - Returns: 主要操作を通知するボタン。
    private func actionButton(_ action: UnassignedObservedVINWarningPrimaryAction) -> some View {
        Button {
            send(action)
        } label: {
            Label(LocalizedStringKey(action.titleKey), systemImage: action.systemImageName)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: IOSUnassignedObservedVINWarningMetrics.actionMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("ios-unassigned-vin-warning-action")
    }
}
#endif
