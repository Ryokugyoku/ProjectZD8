import Foundation

/// 正応答payloadを取得時PID定義で評価し、証跡用の分類と表示用の観測へ変換します。
nonisolated struct OBDPIDPayloadDecoder: Sendable {
    /// 取得時定義の制限付き数式を評価します。
    private let evaluator: OBDPIDFormulaEvaluator

    /// 数式評価器を固定します。
    ///
    /// 責務: payload評価に使う評価器を注入します。
    /// - Parameter evaluator: 取得時定義の数式評価器。
    init(evaluator: OBDPIDFormulaEvaluator = .init()) {
        self.evaluator = evaluator
    }

    /// 1件の正応答payloadを評価します。
    ///
    /// 責務: payloadをdecode・有限値・明示rangeの分類と、有限値なら表示用観測へ変換します。
    /// - Parameters:
    ///   - payload: 未デコード正応答bytes。
    ///   - definition: 数式と任意の両端range、表示metadataを持つ取得時定義。
    ///   - observedAt: 表示用観測に付ける観測日時。
    /// - Returns: 値の評価結果と、有限値が得られた場合の表示用観測。
    func decode(_ payload: [UInt8], definition: OBDPIDDefinition, observedAt: Date) -> OBDPIDPayloadDecoding {
        let value: Double
        do {
            value = try evaluator.evaluate(definition, bytes: payload)
        } catch OBDPIDFormulaError.nonFiniteResult {
            return OBDPIDPayloadDecoding(valueOutcome: .invalidValue, sample: nil)
        } catch {
            return OBDPIDPayloadDecoding(valueOutcome: .decodeFailure, sample: nil)
        }
        guard value.isFinite else { return OBDPIDPayloadDecoding(valueOutcome: .invalidValue, sample: nil) }
        let sample = makeSample(value: value, definition: definition, observedAt: observedAt)
        if let minimum = definition.minimumValue, let maximum = definition.maximumValue,
           !(minimum...maximum).contains(value) {
            return OBDPIDPayloadDecoding(valueOutcome: .invalidValue, sample: sample)
        }
        return OBDPIDPayloadDecoding(valueOutcome: .decodedValid, sample: sample)
    }

    /// 評価済みの値を表示用観測へ変換します。
    ///
    /// 責務: 1件の数値と取得時定義の表示metadataを数値観測へまとめます。
    /// - Parameters:
    ///   - value: 評価済みの有限値。
    ///   - definition: 表示metadataを持つ取得時定義。
    ///   - observedAt: 観測日時。
    /// - Returns: 表示用の数値観測。
    private func makeSample(value: Double, definition: OBDPIDDefinition, observedAt: Date) -> OBDPIDSample {
        OBDPIDSample(
            request: OBDPIDRequest(service: definition.service, pid: definition.pid),
            nameKey: definition.nameKey,
            value: value,
            unit: definition.unit,
            vehicleModelCode: definition.vehicleModelCode,
            observedAt: observedAt,
            summaryKey: definition.summaryKey,
            highValueKey: definition.highValueKey,
            lowValueKey: definition.lowValueKey,
            correlationKey: definition.correlationKey
        )
    }
}
