/// 実PID読取手段がないプラットフォームの明示的境界です。
struct UnavailableOBDPIDTelemetryAdapter: OBDPIDTelemetryPort {
    /// 全要求を利用不能として終了します。
    ///
    /// 責務: 実車PID読取未提供状態を假成功に変換せず返します。
    /// - Parameters:
    ///   - requests: 実行しないPID要求。
    ///   - endpoint: 使用しない接続終端。
    /// - Returns: この実装は常に失敗するため返しません。
    /// - Throws: 常に `OBDPIDTelemetryError.unavailable`。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        throw OBDPIDTelemetryError.unavailable
    }
}
