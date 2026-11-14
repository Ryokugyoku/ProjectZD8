import SwiftUI

/// alert ボタンの役割を表す型の汎用契約です。
///
/// `cancel` と `destructive` のケースを持つ enum は宣言だけで準拠できます。
/// それ以外の値は役割なしとして描画します。
protocol ActionAlertButtonRoleRepresentable: Equatable {
    /// 取り消し操作を表す値です。
    static var cancel: Self { get }
    /// 破壊的操作を表す値です。
    static var destructive: Self { get }
}

extension ActionAlertButtonRoleRepresentable {
    /// SwiftUI のボタンへ渡す役割です。
    ///
    /// 責務: 1件の役割値を `ButtonRole.cancel`、`ButtonRole.destructive`、役割なしのいずれかへ変換します。
    var buttonRole: ButtonRole? {
        switch self {
        case .cancel: .cancel
        case .destructive: .destructive
        default: nil
        }
    }
}
