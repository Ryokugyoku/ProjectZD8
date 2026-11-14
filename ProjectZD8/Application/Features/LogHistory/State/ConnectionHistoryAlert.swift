/// 接続履歴画面に提示する1件の alert の内容です。
struct ConnectionHistoryAlert: Equatable {
    /// alert の種類です。
    let kind: ConnectionHistoryAlertKind
    /// タイトルのローカライズキーです。View 側で `LocalizedStringKey` に包みます。
    let titleKey: String
    /// 本文です。
    let message: ConnectionHistoryAlertMessage
    /// 表示順に並べたボタンです。
    let buttons: [ConnectionHistoryAlertButton]
    /// alert がボタン以外の経路も含めて閉じられた時に送出する履歴操作です。
    let dismissAction: ConnectionHistoryAction

    /// alert の表示内容と閉じた時の操作を固定して生成します。
    ///
    /// 責務: 1件の alert のタイトル、本文、ボタン、閉じる操作を不変の組へまとめます。
    /// - Parameters:
    ///   - kind: alert の種類。
    ///   - titleKey: タイトルのローカライズキー。
    ///   - message: 本文。
    ///   - buttons: 表示順に並べたボタン。
    ///   - dismissAction: alert が閉じられた時に送出する履歴操作。
    init(
        kind: ConnectionHistoryAlertKind,
        titleKey: String,
        message: ConnectionHistoryAlertMessage,
        buttons: [ConnectionHistoryAlertButton],
        dismissAction: ConnectionHistoryAction
    ) {
        self.kind = kind
        self.titleKey = titleKey
        self.message = message
        self.buttons = buttons
        self.dismissAction = dismissAction
    }
}
