import Foundation
@testable import ProjectZD8

/// アーカイブの読み取りの偽物です。台本どおりに進捗を通知し、記録を順に渡し、要約を返すか失敗します。
///
/// `blockBeforeRecordIndex` を指定すると、その番号の記録を渡す前に門(`gate`)で止まります。
nonisolated final class RoadRegulationArchiveReaderFake: RoadRegulationArchiveReaderPort, @unchecked Sendable {
    /// 読み取りの台本です。
    nonisolated struct Script: Sendable {
        /// 記録より前に通知する進捗です。
        var progressSteps: [RoadRegulationArchiveReadProgress] = []
        /// 順に渡す記録です。
        var records: [RoadRegulationArchiveRecord] = []
        /// 返す要約です。
        var summary: RoadRegulationArchiveSummary
        /// 全記録を渡した後に投げるエラーです。
        var failure: RoadRegulationImportError?
        /// この番号の記録を渡す前に門で止まります。
        var blockBeforeRecordIndex: Int?
    }

    /// 呼び出しを全体の順に記録する帳面です。
    let log: RoadRegulationImportCallLog
    /// 読み取りを止める門です(閉じた時だけ止まります)。
    let gate = RoadRegulationTestGate(isOpen: false)

    /// 状態を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した台本です。
    private var storedScript: Script
    /// ロックで保護した、読まれたファイルです。
    private var storedReadURLs: [URL] = []
    /// ロックで保護した、`consume` へ渡した記録の数です。
    private var storedConsumedCount = 0

    /// 責務: 台本を指定して偽物を作ります。
    init(script: Script, log: RoadRegulationImportCallLog) {
        storedScript = script
        self.log = log
    }

    /// 責務: 台本を差し替えます。
    func replaceScript(_ script: Script) {
        lock.withLock { storedScript = script }
    }

    /// 読まれたファイルです(読まれた順)。
    var readURLs: [URL] { lock.withLock { storedReadURLs } }
    /// `consume` へ渡した記録の数です。
    var consumedCount: Int { lock.withLock { storedConsumedCount } }

    /// 責務: 台本どおりに進捗を通知し、記録を渡し、要約を返すか失敗します。`consume` のエラーはそのまま投げます。
    func read(
        archiveAt url: URL,
        progress: (RoadRegulationArchiveReadProgress) -> Void,
        consume: (RoadRegulationArchiveRecord) throws -> Void
    ) throws -> RoadRegulationArchiveSummary {
        log.record(.read)
        let script = lock.withLock { () -> Script in
            storedReadURLs.append(url)
            return storedScript
        }
        script.progressSteps.forEach(progress)
        for (index, record) in script.records.enumerated() {
            if index == script.blockBeforeRecordIndex { try gate.waitSync() }
            try consume(record)
            lock.withLock { storedConsumedCount += 1 }
        }
        if let failure = script.failure { throw failure }
        return script.summary
    }
}
