import Foundation

/// ELM/STNの単一Service 01応答からPIDデータバイトを抽出します。
nonisolated struct ELM327PIDResponseParser {
    /// 指定Service/PIDの正応答からデータバイトを取り出します。
    ///
    /// 責務: 1件のELM応答を要求と一致する正応答ペイロードへ変換します。
    /// - Parameters:
    ///   - response: プロンプトを除いた加工前応答。
    ///   - request: 期待するService/PID。
    /// - Returns: ServiceとPIDを除いたデータバイト。
    /// - Throws: 拒否応答、正応答不在、または空ペイロードの場合は `OBDPIDTelemetryError`。
    func parse(_ response: String, request: OBDPIDRequest) throws -> [UInt8] {
        let normalized = response.uppercased()
        let rejected = ["?", "NO DATA", "UNABLE TO CONNECT", "BUS ERROR", "CAN ERROR", "STOPPED"]
        guard !rejected.contains(where: normalized.contains) else { throw OBDPIDTelemetryError.commandRejected }
        let bytes = response
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "\r") }
            .filter { !$0.localizedCaseInsensitiveContains("SEARCHING") }
            .flatMap { hexBytes(in: $0) }
        let responseService = request.service | 0x40
        guard let start = bytes.indices.first(where: {
            $0 + 1 < bytes.count && bytes[$0] == responseService && bytes[$0 + 1] == request.pid
        }) else { throw OBDPIDTelemetryError.malformedResponse }
        let payload = Array(bytes.dropFirst(start + 2))
        guard !payload.isEmpty else { throw OBDPIDTelemetryError.malformedResponse }
        return payload
    }

    /// 1行の空白区切り16進トークンをバイトへ変換します。
    ///
    /// 責務: ELM応答行の2桁16進トークンだけを順序通り取り出します。
    /// - Parameter line: 解析する1行。
    /// - Returns: 解析できたバイト列。
    private func hexBytes(in line: String) -> [UInt8] {
        line.split(whereSeparator: \.isWhitespace).compactMap { token in
            guard token.count == 2 else { return nil }
            return UInt8(token, radix: 16)
        }
    }
}
