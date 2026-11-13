import Foundation

/// ELM/STNが返した1件のPID要求への応答を分類します。
nonisolated struct ELM327ResponseParser: Sendable {
    /// 応答の分類結果です。
    enum Result: Equatable, Sendable {
        /// 要求に一致する正応答。サービスとPIDのエコーを除いたデータです。
        case data([UInt8])
        /// 車両がデータ無し(NO DATA)と応答した。
        case noData
        /// アダプターまたはバスのエラー応答だった。
        case rejected
        /// 別の要求への正応答だった(直前のタイムアウトの遅延応答など)。
        case otherResponse
        /// 解釈できない、またはペイロードが空だった。
        case unrecognized
    }

    /// 応答全体を拒否とみなす語です。
    private static let rejectionTokens = [
        "?", "UNABLE TO CONNECT", "BUS ERROR", "CAN ERROR", "STOPPED", "BUS BUSY",
        "BUFFER FULL", "FB ERROR", "DATA ERROR", "LV RESET", "ACT ALERT", "ERROR"
    ]

    /// パーサーを生成します。
    ///
    /// 責務: 状態を持たない応答パーサーを構築します。
    init() {}

    /// 責務: プロンプトを除いた1件の応答を、指定要求に対する分類結果へ変換します。
    /// - Parameters:
    ///   - response: `>` を除いた加工前応答。
    ///   - request: 送信した要求。
    func parse(_ response: String, request: OBDPIDRequest) -> Result {
        let normalized = response.uppercased()
        if normalized.contains("NO DATA") { return .noData }
        if Self.rejectionTokens.contains(where: normalized.contains) { return .rejected }
        let bytes = response
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "\r") }
            .filter { !$0.localizedCaseInsensitiveContains("SEARCHING") }
            .flatMap(hexBytes(in:))
        let responseService = request.service | 0x40
        if let start = bytes.indices.first(where: {
            $0 + 1 < bytes.count && bytes[$0] == responseService && bytes[$0 + 1] == request.pid
        }) {
            let payload = Array(bytes.dropFirst(start + 2))
            return payload.isEmpty ? .unrecognized : .data(payload)
        }
        if let first = bytes.first, first >> 4 == 0x4 || first >> 4 == 0x6 {
            return .otherResponse
        }
        return .unrecognized
    }

    /// 責務: 1行の空白区切り2桁16進トークンだけを順序通りバイトへ変換します。
    private func hexBytes(in line: String) -> [UInt8] {
        line.split(whereSeparator: \.isWhitespace).compactMap { token in
            guard token.count == 2 else { return nil }
            return UInt8(token, radix: 16)
        }
    }
}
