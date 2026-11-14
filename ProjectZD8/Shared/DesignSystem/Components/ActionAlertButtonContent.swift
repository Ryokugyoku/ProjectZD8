/// `ActionAlertContent` に並べるボタン1件の汎用契約です。
protocol ActionAlertButtonContent {
    /// 押下時に送る型付き Action です。
    associatedtype Action
    /// ボタンの役割です。
    associatedtype Role: ActionAlertButtonRoleRepresentable

    /// ボタン文言のローカライズキーです。
    var titleKey: String { get }
    /// ボタンの役割です。
    var role: Role { get }
    /// 押下時に送る Action です。
    var action: Action { get }
}
