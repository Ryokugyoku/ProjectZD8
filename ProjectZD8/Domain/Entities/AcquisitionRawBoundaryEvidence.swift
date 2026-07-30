import Foundation

/// Raw取得の進行に合わせて追記する不変境界eventです。
nonisolated enum AcquisitionRawBoundaryEvidence: Equatable, Sendable {
    /// 最初のRaw要求を許可する直前の開始境界です。
    case started(at: Date)
    /// Raw取得が停止した時刻と直接原因を保持する終了境界です。
    case ended(at: Date, reason: ConnectionSessionEndReason)

    /// eventが示す境界時刻です。
    var occurredAt: Date {
        switch self {
        case let .started(at), let .ended(at, _):
            at
        }
    }
}
