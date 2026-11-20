import Foundation

/// 軌跡の1点の周りにある規制の候補と、その点が規制データの範囲内かどうかです。
nonisolated struct RoadRegulationCandidateContext: Equatable, Sendable {
    /// 周辺の規制(行 ID の昇順・重複なし)。
    let regulations: [RoadRegulation]
    /// 点が取得済みのどれかの版の範囲(外接矩形)に入っているか。
    let isInsideDataCoverage: Bool
}
