/// 型付き Action を送る alert 1件の表示内容を表す、機能知識を持たない汎用契約です。
///
/// 機能側の alert 記述型は同名のプロパティを持つだけで準拠でき、`View.actionAlerts(_:send:message:)` で描画できます。
protocol ActionAlertContent {
    /// ボタン押下と閉じる操作で送る型付き Action です。
    associatedtype Action
    /// 本文の表示元です。描画方法は呼び出し側のクロージャが決めます。
    associatedtype Message
    /// alert に並べるボタン記述です。
    associatedtype Button: ActionAlertButtonContent where Button.Action == Action

    /// タイトルのローカライズキーです。
    var titleKey: String { get }
    /// 本文の表示元です。
    var message: Message { get }
    /// 表示順に並んだボタン記述です。
    var buttons: [Button] { get }
    /// ボタン以外の方法で alert が閉じられた時に送る Action です。
    var dismissAction: Action { get }
}
