/// iPhoneからセッションRawログを除去する前の判断結果です。
enum ConnectionSessionLocalRemovalDecision: Equatable, Sendable {
    /// Mac受領証が現在Manifestと一致するため標準確認で除去できます。
    case safe
    /// Mac取込を確認できないためデータ消失警告が必要です。
    case requiresDataLossWarning
    /// 取得中またはRawログが存在しないため除去できません。
    case unavailable
}

/// セッション状態とMac受領証からiPhoneローカル除去可否を決定します。
struct ConnectionSessionLocalRemovalPolicy {
    /// セッションの現在状態からローカル除去判断を返します。
    ///
    /// 責務: 1件の接続セッションを安全、警告必須、利用不能のいずれかへ分類します。
    /// - Parameter session: 除去対象として選ばれた接続セッション。
    /// - Returns: 現在の端末内RawログとMac取込証跡に対応する判断。
    func decision(for session: ConnectionSession) -> ConnectionSessionLocalRemovalDecision {
        guard session.endedAt != nil,
              session.rawLogSummary.localState == .available,
              session.rawLogSummary.recordCount > 0 else {
            return .unavailable
        }
        return session.rawLogSummary.isDurablyImportedByMac ? .safe : .requiresDataLossWarning
    }
}
