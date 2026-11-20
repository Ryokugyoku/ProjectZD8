import Foundation

/// 位置記録の状態変化です。軌跡が無い理由や途中からの記録を表します。
nonisolated struct ConnectionSessionLocationEvent: Equatable, Sendable {
    /// セッション内の番号(昇順)。
    let ordinal: Int
    /// 状態が変化した実時間。
    let occurredAt: Date
    /// 状態の種類。
    let kind: ConnectionSessionLocationEventKind
}
