/// 接続履歴の状態表示が持つ意味上の色調です。
///
/// Application 層は SwiftUI の `Color` を扱えないため、View 側がこの値を具体色へ1対1で対応させます。
enum ConnectionHistoryStatusTone: CaseIterable, Equatable, Sendable {
    /// 補助的な無彩色の表示です(現行の `.secondary`)。
    case neutral
    /// 待機や注意を示す表示です(現行の `.orange`)。
    case caution
    /// 完了や安全を示す表示です(現行の `.green`)。
    case positive
    /// 失敗を示す表示です(現行の `.red`)。
    case critical
    /// 利用可能な情報を示す表示です(現行の `.blue`)。
    case informative
}
