import Foundation

/// セッションRawログ解析の読込範囲をAnalysisへ通知します。
enum SessionLogAnalysisAction: Equatable {
    /// 指定セッションの保存済みRawログ解析を要求します。
    case sessionSelected(ConnectionSession)
    /// 確認済みのiCloud Rawログ取得と解析を要求します。
    case downloadConfirmed
    /// iCloud Rawログ取得の確認を取り消します。
    case downloadCancelled
    /// 現在表示中の解析結果を閉じます。
    case dismissed
}
