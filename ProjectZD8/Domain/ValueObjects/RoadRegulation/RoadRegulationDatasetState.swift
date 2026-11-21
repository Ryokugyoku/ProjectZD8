import Foundation

/// 交通規制データの版の状態です。`rawValue` は DB の CHECK 制約に固定されています。
nonisolated enum RoadRegulationDatasetState: String, CaseIterable, Sendable {
    /// 取り込み中(検索には使わない)。
    case importing
    /// 有効(検索に使う。1都道府県に1つまで)。
    case active
    /// 新しい版に置き換わり、削除を待つ。
    case retired
}
