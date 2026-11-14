#if os(macOS)
/// 共通の接続履歴 alert 記述を、Shared の汎用 alert 描画へ接続します。
///
/// プロパティ名が汎用契約と一致するため、準拠宣言だけで描画できます。
extension ConnectionHistoryAlert: ActionAlertContent {}

/// 共通の接続履歴 alert ボタンを、Shared の汎用 alert ボタン契約へ接続します。
extension ConnectionHistoryAlertButton: ActionAlertButtonContent {}

/// 共通の接続履歴 alert ボタン役割を、SwiftUI のボタン役割へ変換できるようにします。
extension ConnectionHistoryAlertButton.Role: ActionAlertButtonRoleRepresentable {}
#endif
