import Foundation

/// JARTIC の CSV の1行の解釈を、途中で「読み飛ばし」か「捨てる」に決めて止める時に投げる値です。
///
/// 設計書 §3.1 の規則を上から順に適用し、最初に当てはまった規則の結果で止めるために使います。
/// 取り込み全体の失敗ではなく、1行の結果(`RoadRegulationArchiveRecord`)を運ぶだけです。
nonisolated struct JARTICRegulationRowStop: Error, Equatable, Sendable {
    /// その行の結果(`skipped` か `rejected`)。
    let record: RoadRegulationArchiveRecord

    /// 理由つきで捨てる時の値を作ります。
    ///
    /// 責務: 捨てる理由を1行の結果に包みます。
    /// - Parameter reason: 捨てる理由。
    /// - Returns: `rejected(reason)` を運ぶ値。
    static func rejected(_ reason: RoadRegulationRowRejection) -> JARTICRegulationRowStop {
        JARTICRegulationRowStop(record: .rejected(reason))
    }

    /// 読み飛ばす時の値を作ります。
    ///
    /// 責務: 読み飛ばす理由を1行の結果に包みます。
    /// - Parameter reason: 読み飛ばす理由。
    /// - Returns: `skipped(reason)` を運ぶ値。
    static func skipped(_ reason: RoadRegulationRowSkipReason) -> JARTICRegulationRowStop {
        JARTICRegulationRowStop(record: .skipped(reason))
    }
}
