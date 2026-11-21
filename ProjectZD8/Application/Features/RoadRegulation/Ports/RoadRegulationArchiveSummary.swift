import Foundation

/// ZIP を最後まで読んだ時に分かる情報です。
nonisolated struct RoadRegulationArchiveSummary: Equatable, Sendable {
    /// CSV のエントリ名から読んだ基準月。読めなければ `nil`。
    let dataMonth: RoadRegulationDataMonth?
    /// CSV の版(例 "k_2.1")。
    let formatVersion: String
    /// データ行の総数。
    let totalRows: Int
}
