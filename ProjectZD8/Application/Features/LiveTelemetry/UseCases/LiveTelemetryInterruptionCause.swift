/// 取得が途切れた直接原因です。
nonisolated enum LiveTelemetryInterruptionCause: Equatable, Sendable {
    /// 最後の正応答から途絶閾値以上、車両の応答がありません。
    case responseStall
    /// アダプターまたは車両との通信境界を失いました。
    case linkLost

    /// 途切れた区間を閉じる理由を返します。
    ///
    /// 責務: 途切れの原因を連続取得区間の終了理由へ変換します。
    var segmentEndReason: ConnectionSessionSegmentEndReason {
        switch self {
        case .responseStall: .responseStall
        case .linkLost: .linkLost
        }
    }

    /// 区間の間に記録する欠損の原因を返します。
    ///
    /// 責務: 途切れの原因を欠損の原因へ変換します。
    var gapCause: ConnectionSessionGapCause {
        switch self {
        case .responseStall: .responseStall
        case .linkLost: .linkLost
        }
    }

    /// 猶予を超えて終了したときのセッションの終了原因を返します。
    ///
    /// 責務: 途切れの原因を既存の接続セッション終了原因へ変換します。
    var sessionEndReason: ConnectionSessionEndReason {
        switch self {
        case .responseStall: .vehicleNoResponse
        case .linkLost: .connectionLost
        }
    }
}
