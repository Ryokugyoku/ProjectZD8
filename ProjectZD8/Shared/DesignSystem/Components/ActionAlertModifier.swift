import SwiftUI

/// 任意の `ActionAlertContent` を1つの `.alert` として描画し、操作を型付き Action で返します。
struct ActionAlertModifier<Description: ActionAlertContent>: ViewModifier {
    /// 表示中の alert 記述です。`nil` の時は表示しません。
    let alert: Description?
    /// ボタン押下と閉じる操作の Action 送出先です。
    let send: (Description.Action) -> Void
    /// 本文の表示元を `Text` へ変換します。
    let message: (Description.Message) -> Text

    /// alert 記述を SwiftUI の alert へ接続します。
    ///
    /// 責務: 表示条件、ボタンの並びと役割、閉じた時の Action 送出を1つの alert へ接続します。
    /// - Parameter content: alert を重ねる対象の View。
    /// - Returns: alert を接続した View。
    func body(content: Content) -> some View {
        content.alert(
            Text(LocalizedStringKey(alert?.titleKey ?? "")),
            isPresented: Binding(
                get: { alert != nil },
                set: { isPresented in
                    if !isPresented, let alert { send(alert.dismissAction) }
                }
            ),
            presenting: alert
        ) { presented in
            ForEach(Array(presented.buttons.enumerated()), id: \.offset) { _, button in
                Button(LocalizedStringKey(button.titleKey), role: button.role.buttonRole) { send(button.action) }
            }
        } message: { presented in
            message(presented.message)
        }
    }
}

extension View {
    /// alert 記述の列を、要素ごとに独立した `.alert` として順に接続します。
    ///
    /// 責務: 固定長の alert 記述列を同じ順序の `ActionAlertModifier` 連鎖へ変換します。
    /// - Parameters:
    ///   - alerts: 表示位置ごとの alert 記述。表示しない位置は `nil`。要素数は描画ごとに一定にします。
    ///   - send: ボタン押下と閉じる操作の Action 送出先。
    ///   - message: 本文の表示元を `Text` へ変換するクロージャ。
    /// - Returns: すべての alert を接続した View。
    func actionAlerts<Description: ActionAlertContent>(
        _ alerts: [Description?],
        send: @escaping (Description.Action) -> Void,
        message: @escaping (Description.Message) -> Text
    ) -> some View {
        alerts.reduce(AnyView(self)) { view, alert in
            AnyView(view.modifier(ActionAlertModifier(alert: alert, send: send, message: message)))
        }
    }
}
