import Foundation

/// 日付の絞り込みを有効にした時の初期日を、終了済みセッションの開始日時から決めます。
struct ConnectionHistoryFilterDateFallback {
    /// 開始日の条件を有効にした時の初期日を返します。
    ///
    /// 責務: セッション列の最も早い開始日時を初期日へ変換し、セッションが無ければ `Date.distantPast` を返します。
    /// - Parameter sessions: 初期日の算出元になる終了済みセッション。
    /// - Returns: 開始日の条件の初期日。
    func startDate(in sessions: [ConnectionSession]) -> Date {
        sessions.map(\.startedAt).min() ?? .distantPast
    }

    /// 終了日の条件を有効にした時の初期日を返します。
    ///
    /// 責務: セッション列の最も遅い開始日時を初期日へ変換し、セッションが無ければ `Date.distantPast` を返します。
    /// - Parameter sessions: 初期日の算出元になる終了済みセッション。
    /// - Returns: 終了日の条件の初期日。
    func endDate(in sessions: [ConnectionSession]) -> Date {
        sessions.map(\.startedAt).max() ?? .distantPast
    }
}
