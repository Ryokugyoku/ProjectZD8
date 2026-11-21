import Foundation
@testable import ProjectZD8

/// 交通規制の版の Repository をメモリ上で再現し、呼び出しを記録して、メソッドごとに失敗を注入できる Spy です。
///
/// 版の状態(importing / active / retired)と、版ごとの規制を保持します。同じ版の中で同じユニークキーは2件目から挿入しません
/// (`ON CONFLICT DO NOTHING` と同じ)。有効化は同じ県の旧 active を retired にします。
nonisolated final class RoadRegulationDatasetRepositorySpy: RoadRegulationDatasetRepository, @unchecked Sendable {
    /// 失敗を注入できるメソッドです。
    nonisolated enum Method: Hashable, Sendable {
        /// `activeDatasets()`。
        case activeDatasets
        /// `beginImport(_:)`。
        case beginImport
        /// `appendRegulations(_:to:)`。
        case appendRegulations
        /// `activate(_:summary:activatedAt:)`。
        case activate
        /// `discard(_:)`。
        case discard
        /// `retireActiveDataset(for:)`。
        case retireActiveDataset
        /// `purgeInactiveDatasets()`。
        case purgeInactiveDatasets
    }

    /// 有効化の呼び出しの記録です。
    nonisolated struct Activation: Equatable, Sendable {
        /// 有効化した版です。
        let datasetID: RoadRegulationDatasetID
        /// 渡された要約です。
        let summary: RoadRegulationImportSummary
        /// 渡された有効化の時刻です。
        let activatedAt: Date
    }

    /// 保持している1つの版です。
    private nonisolated struct Stored: Sendable {
        /// 都道府県です。
        let prefecture: JapanesePrefectureCode
        /// 状態です。
        var state: RoadRegulationDatasetState
        /// 開始の時の下書きです(種として入れた版は `nil`)。
        let draft: RoadRegulationDatasetDraft?
        /// 有効化した後の版です。
        var dataset: RoadRegulationDataset?
        /// 挿入した規制です。
        var regulations: [RoadRegulationIndexedDraft] = []
    }

    /// 呼び出しを全体の順に記録する帳面です。
    let log: RoadRegulationImportCallLog

    /// 状態を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、版ごとの保持内容です。
    private var stored: [RoadRegulationDatasetID: Stored] = [:]
    /// ロックで保護した、注入された失敗です。
    private var failures: [Method: RoadRegulationRepositoryError] = [:]
    /// ロックで保護した、書き込みを失敗させる呼び出しの番号(1始まり)です。`nil` なら毎回失敗させます。
    private var appendFailureCallNumber: Int?
    /// ロックで保護した、有効化の後の掃除だけで投げるエラーです。
    private var purgeAfterActivationFailure: RoadRegulationRepositoryError?
    /// ロックで保護した、開始の下書き(呼ばれた順)です。
    private var storedBegunDrafts: [RoadRegulationDatasetDraft] = []
    /// ロックで保護した、開始で返した版(呼ばれた順)です。
    private var storedBegunIDs: [RoadRegulationDatasetID] = []
    /// ロックで保護した、書き込みのまとまり(呼ばれた順)です。
    private var storedAppendedBatches: [[RoadRegulationIndexedDraft]] = []
    /// ロックで保護した、有効化(呼ばれた順)です。
    private var storedActivations: [Activation] = []
    /// ロックで保護した、破棄を頼まれた版(呼ばれた順)です。
    private var storedDiscardedIDs: [RoadRegulationDatasetID] = []
    /// ロックで保護した、退役を頼まれた県(呼ばれた順)です。
    private var storedRetiredPrefectures: [JapanesePrefectureCode] = []
    /// ロックで保護した、掃除の回数です。
    private var storedPurgeCount = 0

    /// 責務: 呼び出しの帳面を指定して、空の Spy を作ります。
    init(log: RoadRegulationImportCallLog = RoadRegulationImportCallLog()) {
        self.log = log
    }

    /// 責務: 有効な版を種として入れます(呼び出しとしては記録しません)。
    func seedActive(_ dataset: RoadRegulationDataset) {
        lock.withLock {
            stored[dataset.id] = Stored(prefecture: dataset.prefecture, state: .active, draft: nil, dataset: dataset)
        }
    }

    /// 責務: 指定の状態の版を種として入れます(掃除の検証用)。
    func seedInactive(_ id: RoadRegulationDatasetID, prefecture: JapanesePrefectureCode, state: RoadRegulationDatasetState) {
        lock.withLock { stored[id] = Stored(prefecture: prefecture, state: state, draft: nil) }
    }

    /// 責務: 指定のメソッドを、指定のエラーで失敗させます(`nil` で成功に戻します)。
    func fail(_ method: Method, with error: RoadRegulationRepositoryError?) {
        lock.withLock { failures[method] = error }
    }

    /// 責務: 指定の番号(1始まり)の書き込みだけを失敗させます。
    func failAppend(onCallNumber number: Int, with error: RoadRegulationRepositoryError) {
        lock.withLock {
            failures[.appendRegulations] = error
            appendFailureCallNumber = number
        }
    }

    /// 責務: 有効化が呼ばれた後の掃除(古い版の掃除)だけを、指定のエラーで失敗させます。
    func failPurgeAfterActivation(with error: RoadRegulationRepositoryError) {
        lock.withLock { purgeAfterActivationFailure = error }
    }

    /// 開始の下書きです(呼ばれた順)。
    var begunDrafts: [RoadRegulationDatasetDraft] { lock.withLock { storedBegunDrafts } }
    /// 開始で返した版です(呼ばれた順)。
    var begunIDs: [RoadRegulationDatasetID] { lock.withLock { storedBegunIDs } }
    /// 書き込みのまとまりです(呼ばれた順)。
    var appendedBatches: [[RoadRegulationIndexedDraft]] { lock.withLock { storedAppendedBatches } }
    /// 有効化です(呼ばれた順)。
    var activations: [Activation] { lock.withLock { storedActivations } }
    /// 破棄を頼まれた版です(呼ばれた順)。
    var discardedIDs: [RoadRegulationDatasetID] { lock.withLock { storedDiscardedIDs } }
    /// 退役を頼まれた県です(呼ばれた順)。
    var retiredPrefectures: [JapanesePrefectureCode] { lock.withLock { storedRetiredPrefectures } }
    /// 掃除の回数です。
    var purgeCount: Int { lock.withLock { storedPurgeCount } }

    /// いま有効な版です(都道府県の昇順。呼び出しとしては記録しません)。
    var currentActiveDatasets: [RoadRegulationDataset] {
        lock.withLock { activeSnapshot() }
    }

    /// まだ残っている、取り込み途中(importing)の版です。
    var importingDatasetIDs: [RoadRegulationDatasetID] {
        lock.withLock { stored.filter { $0.value.state == .importing }.map(\.key) }
    }

    /// まだ残っている、退役した(retired)版です。
    var retiredDatasetIDs: [RoadRegulationDatasetID] {
        lock.withLock { stored.filter { $0.value.state == .retired }.map(\.key) }
    }

    /// 責務: 有効な版を都道府県の昇順で返します。
    func activeDatasets() throws -> [RoadRegulationDataset] {
        log.record(.activeDatasets)
        return try lock.withLock {
            try throwIfFailing(.activeDatasets)
            return activeSnapshot()
        }
    }

    /// 責務: importing の版を作り、その ID を返します。
    func beginImport(_ draft: RoadRegulationDatasetDraft) throws -> RoadRegulationDatasetID {
        log.record(.beginImport)
        return try lock.withLock {
            storedBegunDrafts.append(draft)
            try throwIfFailing(.beginImport)
            let id = RoadRegulationDatasetID(rawValue: UUID())
            stored[id] = Stored(prefecture: draft.prefecture, state: .importing, draft: draft)
            storedBegunIDs.append(id)
            return id
        }
    }

    /// 責務: まとまりを記録し、同じ版の中で未出のユニークキーだけを挿入して、挿入した件数を返します。
    func appendRegulations(_ batch: [RoadRegulationIndexedDraft], to datasetID: RoadRegulationDatasetID) throws -> Int {
        log.record(.appendRegulations(count: batch.count))
        return try lock.withLock {
            storedAppendedBatches.append(batch)
            if shouldFailAppend(callNumber: storedAppendedBatches.count) { try throwIfFailing(.appendRegulations) }
            return insert(batch, into: datasetID)
        }
    }

    /// 責務: 同じ県の旧 active を retired にし、本版を active にして返します。
    func activate(
        _ datasetID: RoadRegulationDatasetID,
        summary: RoadRegulationImportSummary,
        activatedAt: Date
    ) throws -> RoadRegulationDataset {
        log.record(.activate)
        return try lock.withLock {
            storedActivations.append(Activation(datasetID: datasetID, summary: summary, activatedAt: activatedAt))
            try throwIfFailing(.activate)
            guard let entry = stored[datasetID], entry.state == .importing, let draft = entry.draft else {
                throw RoadRegulationRepositoryError.notFound
            }
            retireActive(of: entry.prefecture)
            let dataset = Self.dataset(id: datasetID, draft: draft, summary: summary, activatedAt: activatedAt)
            stored[datasetID]?.state = .active
            stored[datasetID]?.dataset = dataset
            return dataset
        }
    }

    /// 責務: 版と、その規制を消します。
    func discard(_ datasetID: RoadRegulationDatasetID) throws {
        log.record(.discard)
        try lock.withLock {
            storedDiscardedIDs.append(datasetID)
            try throwIfFailing(.discard)
            stored[datasetID] = nil
        }
    }

    /// 責務: 県の active を retired にし、あったかどうかを返します。
    func retireActiveDataset(for prefecture: JapanesePrefectureCode) throws -> Bool {
        log.record(.retireActiveDataset)
        return try lock.withLock {
            storedRetiredPrefectures.append(prefecture)
            try throwIfFailing(.retireActiveDataset)
            return retireActive(of: prefecture)
        }
    }

    /// 責務: retired と importing の版を消します。
    func purgeInactiveDatasets() throws {
        log.record(.purgeInactiveDatasets)
        try lock.withLock {
            storedPurgeCount += 1
            try throwIfFailing(.purgeInactiveDatasets)
            if let failure = purgeAfterActivationFailure, !storedActivations.isEmpty { throw failure }
            stored = stored.filter { $0.value.state == .active }
        }
    }

    /// 責務: 版の中で、挿入した規制を返します(ユニークキーの重複は除かれています)。
    func regulations(in datasetID: RoadRegulationDatasetID) -> [RoadRegulationIndexedDraft] {
        lock.withLock { stored[datasetID]?.regulations ?? [] }
    }

    /// 責務: ロックの中で、有効な版を都道府県の昇順で集めます。
    private func activeSnapshot() -> [RoadRegulationDataset] {
        stored.values.filter { $0.state == .active }.compactMap(\.dataset).sorted { $0.prefecture < $1.prefecture }
    }

    /// 責務: ロックの中で、注入された失敗があれば投げます。
    private func throwIfFailing(_ method: Method) throws {
        if let error = failures[method] { throw error }
    }

    /// 責務: ロックの中で、この番号の書き込みを失敗させるかを返します。
    private func shouldFailAppend(callNumber: Int) -> Bool {
        guard let target = appendFailureCallNumber else { return true }
        return callNumber == target
    }

    /// 責務: ロックの中で、未出のユニークキーだけを挿入して件数を返します。
    private func insert(_ batch: [RoadRegulationIndexedDraft], into datasetID: RoadRegulationDatasetID) -> Int {
        var existing = Set(stored[datasetID]?.regulations.map(\.draft.uniqueKey) ?? [])
        var inserted = 0
        for item in batch where !existing.contains(item.draft.uniqueKey) {
            existing.insert(item.draft.uniqueKey)
            stored[datasetID]?.regulations.append(item)
            inserted += 1
        }
        return inserted
    }

    /// 責務: ロックの中で、県の active を retired にし、あったかどうかを返します。
    @discardableResult
    private func retireActive(of prefecture: JapanesePrefectureCode) -> Bool {
        let ids = stored.filter { $0.value.state == .active && $0.value.prefecture == prefecture }.map(\.key)
        for id in ids { stored[id]?.state = .retired }
        return !ids.isEmpty
    }

    /// 責務: 下書きと要約から、有効な版の値を作ります。
    private static func dataset(
        id: RoadRegulationDatasetID,
        draft: RoadRegulationDatasetDraft,
        summary: RoadRegulationImportSummary,
        activatedAt: Date
    ) -> RoadRegulationDataset {
        RoadRegulationDataset(
            id: id, prefecture: draft.prefecture, state: .active, dataMonth: summary.dataMonth,
            publicationStamp: draft.publicationStamp, sourceURL: draft.sourceURL, downloadedAt: draft.downloadedAt,
            activatedAt: activatedAt, formatVersion: summary.formatVersion, counts: summary.counts, coverage: summary.coverage
        )
    }
}
