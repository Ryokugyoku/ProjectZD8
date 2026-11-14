/// 接続履歴 alert に並べる1個のボタンです。
struct ConnectionHistoryAlertButton: Equatable {
    /// ボタンの役割です。View 側で SwiftUI の `ButtonRole` へ対応させます。
    enum Role: CaseIterable, Equatable, Sendable {
        /// 役割指定なしの通常ボタンです。
        case normal
        /// 取り消し操作のボタンです。
        case cancel
        /// 不可逆な破壊的操作のボタンです。
        case destructive
    }

    /// ボタン文言のローカライズキーです。View 側で `LocalizedStringKey` に包みます。
    let titleKey: String
    /// ボタンの役割です。
    let role: Role
    /// ボタン押下時に送出する履歴操作です。
    let action: ConnectionHistoryAction

    /// 文言キー、役割、送出操作を固定して生成します。
    ///
    /// 責務: 1個の alert ボタンの表示と操作を不変の組へまとめます。
    /// - Parameters:
    ///   - titleKey: ボタン文言のローカライズキー。
    ///   - role: ボタンの役割。
    ///   - action: ボタン押下時に送出する履歴操作。
    init(titleKey: String, role: Role, action: ConnectionHistoryAction) {
        self.titleKey = titleKey
        self.role = role
        self.action = action
    }
}
