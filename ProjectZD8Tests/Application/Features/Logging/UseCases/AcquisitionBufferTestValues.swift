import Foundation
@testable import ProjectZD8

/// 取得バッファ系の純粋型のテストが共有する値を生成します。
enum AcquisitionBufferTestValues {
    /// Transport結果の分類部品です。
    static let classifier = AcquisitionTransportOutcomeClassifier()

    /// 指定秒の日時を返します。
    ///
    /// 責務: 1970年起点の秒を日時へ変換します。
    /// - Parameter seconds: 1970年からの秒。
    /// - Returns: 日時。
    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    /// 未完了のbatchを生成します。
    ///
    /// 責務: 指定番号・開始日時・manifest位置の要求列を持つ未完了batchを返します。
    /// - Parameters:
    ///   - ordinal: batch番号。
    ///   - startedAt: 開始日時の秒。
    ///   - manifestOrdinals: 要求ごとのmanifest位置。
    /// - Returns: 未完了batch。
    /// - Throws: batch番号が不正な場合のエラー。
    static func batch(_ ordinal: Int64, startedAt: TimeInterval = 10, manifestOrdinals: [Int] = [0]) throws -> AcquisitionBufferedBatch {
        AcquisitionBufferedBatch(
            identity: try AcquisitionBatchIdentity(ordinal: ordinal),
            generation: 1,
            policyTick: UInt(ordinal),
            startedAt: date(startedAt),
            manifestPIDOrdinals: manifestOrdinals
        )
    }

    /// 保存待ちのRawを生成します。
    ///
    /// 責務: 観測日時・区間番号・payloadだけを差し替えたRawを返します。
    /// - Parameters:
    ///   - observedAt: 観測日時の秒。
    ///   - segment: 区間番号。
    ///   - payload: 正応答bytes。
    /// - Returns: 保存待ちのRaw。
    static func raw(observedAt: TimeInterval = 11, segment: Int = 0, payload: [UInt8] = [1]) -> AcquisitionBufferedRaw {
        AcquisitionBufferedRaw(
            observedAt: date(observedAt),
            monotonicNanoseconds: 1_000 + UInt64(observedAt),
            segmentOrdinal: segment,
            elapsedNanoseconds: 50,
            request: OBDPIDRequest(service: 0x01, pid: 0x0C),
            payload: payload
        )
    }

    /// 要求1件へ正応答を記録します。
    ///
    /// 責務: 指定Rawを参照する正応答として要求を終端させます。
    /// - Parameters:
    ///   - batch: 記録先batch。
    ///   - requestOrdinal: 要求順。
    ///   - raw: 正応答のRaw。
    /// - Throws: 順序不正などの記録エラー。
    static func respond(_ batch: inout AcquisitionBufferedBatch, _ requestOrdinal: Int, raw: AcquisitionBufferedRaw = raw()) throws {
        try batch.record(
            requestOrdinal: requestOrdinal, transportOutcome: .responded, valueOutcome: .decodedValid,
            elapsedNanoseconds: 50, reasonCode: nil, raw: raw
        )
    }

    /// 要求1件へ非応答の結果を記録します。
    ///
    /// 責務: Rawを持たない結果として要求を終端させます。
    /// - Parameters:
    ///   - batch: 記録先batch。
    ///   - requestOrdinal: 要求順。
    ///   - outcome: 非応答のTransport結果。
    /// - Throws: 順序不正などの記録エラー。
    static func fail(_ batch: inout AcquisitionBufferedBatch, _ requestOrdinal: Int, _ outcome: PIDRequestTransportOutcome) throws {
        try batch.record(
            requestOrdinal: requestOrdinal, transportOutcome: outcome, valueOutcome: .notEvaluated,
            elapsedNanoseconds: 60, reasonCode: "test_reason", raw: nil
        )
    }

    /// 全要求へ正応答を記録して完了させたbatchを返します。
    ///
    /// 責務: Raw付きの完了batchを1件生成します。
    /// - Parameters:
    ///   - ordinal: batch番号。
    ///   - raws: 要求ごとのRaw。
    ///   - completedAt: 完了日時の秒。
    /// - Returns: 完了batch。
    /// - Throws: 記録エラー。
    static func completedBatch(_ ordinal: Int64, raws: [AcquisitionBufferedRaw], completedAt: TimeInterval = 12) throws -> AcquisitionBufferedBatch {
        var built = try batch(ordinal, startedAt: 10, manifestOrdinals: Array(0..<raws.count))
        for (index, raw) in raws.enumerated() { try respond(&built, index, raw: raw) }
        try built.complete(at: date(completedAt), classifier: classifier)
        return built
    }
}
