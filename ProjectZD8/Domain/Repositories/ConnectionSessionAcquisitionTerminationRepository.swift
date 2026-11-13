import Foundation

/// 接続sessionと取得証拠を部分成功なしで終了・回復する能力です。
nonisolated protocol ConnectionSessionAcquisitionTerminationRepository {
    /// 現在session、open batch、取得終了境界を1回の永続操作で確定します。
    ///
    /// 責務: 1件の接続sessionを未確定取得証拠の回復を含む原子的な終了状態へ変換します。
    /// - Parameters:
    ///   - session: 終了直前の現在session。
    ///   - endedAt: sessionと取得境界へ共通で使用する終了日時。
    ///   - reason: 接続と取得が停止した直接原因。
    /// - Returns: 永続化後にcanonical readbackした終了済みsession。
    /// - Throws: session不在、競合、取得開始欠落、または原子保存失敗。
    func finishSessionAcquisition(
        _ session: ConnectionSession,
        endedAt: Date,
        reason: ConnectionSessionEndReason
    ) throws -> ConnectionSession

    /// アカウントに残る未終了sessionとopen取得証拠を原子的に回復します。
    ///
    /// 責務: process終了後に残った各sessionを決定的な異常終了状態へ回復します。
    /// - Parameters:
    ///   - accountIdentifier: 回復対象sessionの所有アカウント。
    ///   - recoveredAt: 回復結果へ固定する終了日時。
    /// - Returns: 今回回復した終了済みsession。
    /// - Throws: 保存値不正または原子回復失敗。
    func recoverInterruptedSessionAcquisitions(
        for accountIdentifier: String,
        recoveredAt: Date
    ) throws -> [ConnectionSession]
}
