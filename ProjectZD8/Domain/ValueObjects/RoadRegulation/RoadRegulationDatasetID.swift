import Foundation

/// 取り込んだ交通規制データの版(1都道府県・1回の取り込み)を識別します。
nonisolated struct RoadRegulationDatasetID: Hashable, Sendable {
    /// 版の UUID です。
    let rawValue: UUID
}
