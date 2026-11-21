import Foundation
@testable import ProjectZD8

/// 升目から規制を引く Repository の偽物です。決めた規制を返し、受け取った升目の集合を記録し、失敗を注入できます。
nonisolated final class RoadRegulationQueryRepositoryFake: RoadRegulationQueryRepository, @unchecked Sendable {
    /// 記録と設定を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、返す規制です。
    private var storedRegulations: [RoadRegulation]
    /// ロックで保護した、投げるエラーです。
    private var storedError: RoadRegulationRepositoryError?
    /// ロックで保護した、呼び出しごとに受け取った升目の集合です。
    private var storedRequests: [Set<RoadRegulationCellKey>] = []

    /// 責務: 返す規制を決めて偽物を作ります。
    /// - Parameter regulations: 返す規制。
    init(regulations: [RoadRegulation] = []) {
        storedRegulations = regulations
    }

    /// 呼び出しごとに受け取った升目の集合です(呼ばれた順)。
    var requests: [Set<RoadRegulationCellKey>] {
        lock.withLock { storedRequests }
    }

    /// 責務: 返す規制を置き換えます。
    /// - Parameter regulations: 返す規制。
    func replaceRegulations(_ regulations: [RoadRegulation]) {
        lock.withLock { storedRegulations = regulations }
    }

    /// 責務: 以降の検索で投げるエラーを決めます(`nil` で失敗をやめる)。
    /// - Parameter error: 投げるエラー。
    func fail(with error: RoadRegulationRepositoryError?) {
        lock.withLock { storedError = error }
    }

    /// 責務: 升目の集合を記録し、失敗の指定があれば投げ、なければ決めた規制を返します。
    /// - Parameter cells: 調べる升目。
    /// - Returns: 決めた規制。
    /// - Throws: 失敗の指定があればそのエラー。
    func regulations(inCells cells: Set<RoadRegulationCellKey>) throws -> [RoadRegulation] {
        try lock.withLock {
            storedRequests.append(cells)
            if let storedError { throw storedError }
            return storedRegulations
        }
    }
}
