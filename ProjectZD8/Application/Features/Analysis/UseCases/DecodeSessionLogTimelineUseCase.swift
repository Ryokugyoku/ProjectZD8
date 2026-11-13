import Foundation

/// 保存済みRawログへPID定義の数式を適用し時系列表示値を作成します。
struct DecodeSessionLogTimelineUseCase {
    /// Rawログを復元する永続化境界です。
    private let rawLogRepository: any ConnectionSessionRawLogRepository
    /// PID定義を復元する永続化境界です。
    private let definitionRepository: any OBDPIDDefinitionRepository
    /// 保存済み数式を評価するDomainポリシーです。
    private let evaluator: OBDPIDFormulaEvaluator
    /// 1回の画面反映で変換する最大Rawログ件数です。
    private let batchSize: Int

    /// 永続化境界と評価器を注入して生成します。
    ///
    /// 責務: セッション時系列変換に必要な読取境界と式評価器を固定します。
    /// - Parameters:
    ///   - rawLogRepository: 保存済みRawログの取得先。
    ///   - definitionRepository: PID変換定義の取得先。
    ///   - evaluator: 定義数式を評価するポリシー。
    ///   - batchSize: 1回の進捗通知へ含める最大件数。
    init(rawLogRepository: any ConnectionSessionRawLogRepository, definitionRepository: any OBDPIDDefinitionRepository, evaluator: OBDPIDFormulaEvaluator = .init(), batchSize: Int = 128) {
        self.rawLogRepository = rawLogRepository
        self.definitionRepository = definitionRepository
        self.evaluator = evaluator
        self.batchSize = max(1, batchSize)
    }

    /// 指定セッションの全Raw PIDを小分けに変換して通知します。
    ///
    /// 責務: 1件のセッションRawログを時系列順の変換済みバッチとして順次公開します。
    /// - Parameters:
    ///   - sessionID: 解析する保存済み接続セッションID。
    ///   - prepared: Rawログ総件数の読込完了通知。
    ///   - batchDecoded: 数式変換を完了した時系列バッチの通知。
    /// - Throws: RawログまたはPID定義を読み込めない場合の永続化エラー、またはキャンセル。
    func execute(
        sessionID: ConnectionSessionID,
        prepared: (Int) -> Void,
        batchDecoded: ([SessionLogAnalysisState.TimelineSample]) -> Void
    ) async throws {
        try Task.checkCancellation()
        let definitions = try definitionRepository.definitions()
        let lookup = Dictionary(uniqueKeysWithValues: definitions.map { (OBDPIDRequest(service: $0.service, pid: $0.pid), $0) })
        prepared(try rawLogRepository.entryCount(for: sessionID))
        var lastSequence: Int64?
        while true {
            try Task.checkCancellation()
            let entries = try rawLogRepository.entries(
                for: sessionID,
                after: lastSequence,
                limit: batchSize
            )
            guard !entries.isEmpty else { break }
            batchDecoded(entries.map { decode($0, definitions: lookup) })
            lastSequence = entries.last?.sequence
            await Task.yield()
        }
    }

    /// 1件のRaw応答へ対応する定義式を適用します。
    ///
    /// 責務: 1件のRaw PID応答を定義有無と評価結果に対応する表示値へ変換します。
    /// - Parameters:
    ///   - entry: 変換するRaw応答。
    ///   - definitions: Service/PIDで索引化したPID定義。
    /// - Returns: 数式変換結果または変換不能理由を保持する表示値。
    private func decode(
        _ entry: ConnectionSessionRawLogEntry,
        definitions: [OBDPIDRequest: OBDPIDDefinition]
    ) -> SessionLogAnalysisState.TimelineSample {
        guard let definition = definitions[OBDPIDRequest(service: entry.service, pid: entry.pid)] else {
            return sample(for: entry, definition: nil, value: nil, failure: .missingDefinition)
        }
        guard definition.isDecodable else {
            return sample(for: entry, definition: definition, value: nil, failure: .unavailableFormula)
        }
        do {
            return sample(for: entry, definition: definition, value: try evaluator.evaluate(definition, bytes: entry.payload), failure: nil)
        } catch {
            return sample(for: entry, definition: definition, value: nil, failure: .invalidPayload)
        }
    }

    /// 1件のRaw応答と定義を表示用サンプルへ変換します。
    ///
    /// 責務: 1件のRaw応答と任意のPID定義を時系列表示値へ固定します。
    /// - Parameters:
    ///   - entry: 変換元のRaw応答。
    ///   - definition: 対応するPID定義。未登録時は `nil`。
    ///   - value: 数式変換後の値。
    ///   - failure: 数値化できなかった理由。
    /// - Returns: 原データ来歴を保持する表示用PIDサンプル。
    private func sample(for entry: ConnectionSessionRawLogEntry, definition: OBDPIDDefinition?, value: Double?, failure: SessionLogAnalysisState.TimelineSample.DecodingFailure?) -> SessionLogAnalysisState.TimelineSample {
        .init(
            sequence: entry.sequence,
            observedAt: entry.observedAt,
            service: entry.service,
            pid: entry.pid,
            nameKey: definition?.nameKey,
            value: value,
            unit: definition?.unit,
            vehicleModelCode: definition?.vehicleModelCode,
            payload: entry.payload,
            decodingFailure: failure
        )
    }
}
