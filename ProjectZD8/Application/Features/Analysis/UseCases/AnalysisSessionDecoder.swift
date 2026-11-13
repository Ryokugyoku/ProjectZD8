import Foundation

/// 1チャンネルを変換した結果です。
nonisolated struct AnalysisDecodedChannel: Equatable, Sendable {
    let pid: SessionPID
    var times: [Double]
    var values: [Double]
    var quality: AnalysisChannelQuality
}

/// 1セッションのRawを、取得時に固定した規則で変換した結果です。
nonisolated struct AnalysisDecodedSession: Equatable, Sendable {
    let session: DriveSession
    let channels: [AnalysisDecodedChannel]
    let gaps: [AnalysisGap]
    /// 終了済みなら記録時間、記録中なら最後のサンプル時刻(秒)です。
    let durationSeconds: Double
}

/// Rawサンプルを読み出して取得時のPIDスナップショットで物理値へ変換します。
nonisolated struct AnalysisSessionDecoder: Sendable {
    /// 1回に読み出すサンプル数の既定値です。
    static let defaultPageSize = 5_000
    /// 応答が途切れた区間を欠測区間として扱う既定の長さ(秒)です。
    static let defaultGapThresholdSeconds = 3.0

    private let sessions: any SessionRepository
    private let pageSize: Int
    private let gapThresholdSeconds: Double

    /// 変換器を生成します。
    ///
    /// 責務: Rawの読み出し元とページ幅・欠測判定の閾値を固定します。
    init(sessions: any SessionRepository, pageSize: Int = defaultPageSize, gapThresholdSeconds: Double = defaultGapThresholdSeconds) {
        precondition(pageSize > 0)
        self.sessions = sessions
        self.pageSize = pageSize
        self.gapThresholdSeconds = gapThresholdSeconds
    }

    /// セッションの全サンプルを順に読み出して変換します。
    ///
    /// 責務: メインアクター外でRawをページ読みし、無効な値を除外して品質を数えます。
    /// - Throws: セッション不在は `AnalysisFailure.sessionNotFound`、Raw未所持は `.rawUnavailable`、
    ///   取得条件に無い要求は `.inconsistentRaw`、永続化の失敗は `.store`。
    @concurrent
    func decode(_ id: SessionID) async throws -> AnalysisDecodedSession {
        let session: DriveSession
        let pids: [SessionPID]
        do {
            guard let found = try await sessions.session(id) else { throw AnalysisFailure.sessionNotFound }
            session = found
            pids = try await sessions.pids(for: id)
        } catch let failure as AnalysisFailure {
            throw failure
        } catch {
            throw AnalysisFailure.store
        }
        guard session.rawAvailability == .local else { throw AnalysisFailure.rawUnavailable }

        var indexByRequest: [OBDPIDRequest: Int] = [:]
        var channels: [AnalysisDecodedChannel] = []
        var definitions: [OBDPIDDefinition?] = []
        for pid in pids {
            indexByRequest[pid.request] = channels.count
            channels.append(AnalysisDecodedChannel(pid: pid, times: [], values: [], quality: AnalysisChannelQuality()))
            definitions.append(Self.definition(from: pid))
        }

        let evaluator = OBDPIDFormulaEvaluator()
        var gaps: [AnalysisGap] = []
        var lastResponseSeconds = 0.0
        var lastElapsedSeconds = 0.0
        var cursor: Int64 = -1
        while true {
            try Task.checkCancellation()
            let page: [SessionSample]
            do {
                page = try await sessions.samples(for: id, afterSequence: cursor, limit: pageSize)
            } catch {
                throw AnalysisFailure.store
            }
            if page.isEmpty { break }
            for sample in page {
                guard let index = indexByRequest[sample.request] else { throw AnalysisFailure.inconsistentRaw }
                let seconds = Double(sample.elapsedMicroseconds) / 1_000_000
                lastElapsedSeconds = max(lastElapsedSeconds, seconds)
                channels[index].quality.requested += 1
                switch sample.outcome {
                case .noData: channels[index].quality.noData += 1
                case .timedOut: channels[index].quality.timedOut += 1
                case .failed: channels[index].quality.failed += 1
                case .responded:
                    channels[index].quality.responded += 1
                    if seconds - lastResponseSeconds > gapThresholdSeconds {
                        gaps.append(AnalysisGap(startSeconds: lastResponseSeconds, endSeconds: seconds))
                    }
                    lastResponseSeconds = seconds
                    guard let definition = definitions[index] else { continue }
                    guard let value = try? evaluator.evaluate(definition, bytes: Array(sample.payload)) else {
                        channels[index].quality.undecodable += 1
                        continue
                    }
                    if let minimum = definition.minimumValue, value < minimum {
                        channels[index].quality.outOfRange += 1
                    } else if let maximum = definition.maximumValue, value > maximum {
                        channels[index].quality.outOfRange += 1
                    } else {
                        channels[index].times.append(AnalysisStatistics.rounded(seconds, places: 3))
                        channels[index].values.append(AnalysisStatistics.rounded(value, places: 4))
                        channels[index].quality.decoded += 1
                    }
                }
            }
            cursor = page[page.count - 1].sequence
            if page.count < pageSize { break }
        }
        let duration = session.duration ?? lastElapsedSeconds
        if session.endedAt != nil, duration - lastResponseSeconds > gapThresholdSeconds, lastResponseSeconds > 0 {
            gaps.append(AnalysisGap(startSeconds: lastResponseSeconds, endSeconds: duration))
        }
        return AnalysisDecodedSession(session: session, channels: channels, gaps: gaps, durationSeconds: duration)
    }

    /// セッションPIDの固定値から変換定義を組み立てます。式を持たない場合は `nil` です。
    ///
    /// 責務: 現行カタログを参照せず、セッションに複写された規則だけで定義を作ります。
    private static func definition(from pid: SessionPID) -> OBDPIDDefinition? {
        guard let count = pid.requiredByteCount, let formula = pid.formula, !formula.isEmpty else { return nil }
        return OBDPIDDefinition(
            service: pid.request.service,
            pid: pid.request.pid,
            header: pid.header,
            nameKey: "",
            requiredByteCount: count,
            formula: formula,
            unit: pid.unit,
            minimumValue: pid.minimumValue,
            maximumValue: pid.maximumValue,
            sourceURI: "",
            revision: pid.definitionRevision
        )
    }
}
