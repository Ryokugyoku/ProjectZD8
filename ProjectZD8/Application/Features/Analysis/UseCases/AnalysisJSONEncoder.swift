import Foundation

/// 分析データをWebワークベンチ向けのJSONへ符号化します。
nonisolated enum AnalysisJSONEncoder {
    /// 責務: メインアクター外で値をISO 8601日付のJSONへ符号化します。
    /// - Throws: 失敗は `AnalysisFailure.encoding`。
    @concurrent
    static func encode<Value: Encodable & Sendable>(_ value: Value) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(value)
        } catch {
            throw AnalysisFailure.encoding
        }
    }
}
