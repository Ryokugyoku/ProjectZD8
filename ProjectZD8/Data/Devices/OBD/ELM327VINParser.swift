import Foundation

/// ELM/STNが整形したService 09 PID 02応答からVINを復元します。
nonisolated struct ELM327VINParser: Sendable {
    /// パーサーを生成します。
    ///
    /// 責務: 状態を持たないVINパーサーを構築します。
    init() {}

    /// 責務: 複数プロトコル形式のMode 09応答から17文字のVINを取り出します。
    /// - Parameter response: プロンプトを除いた加工前応答。
    /// - Returns: 17バイトの表示可能ASCIIとして確認できたVIN。確認できなければ `nil`。
    func parse(_ response: String) -> String? {
        let lines = response
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "\r") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("SEARCHING") }
        return parseCANFormatted(lines) ?? parseLegacyFrames(lines)
    }

    /// 責務: CAN自動整形済みの連番行(`0:` `1:` ...)からMode 09ペイロードを連結して復元します。
    private func parseCANFormatted(_ lines: [String]) -> String? {
        let ordered = lines.compactMap { line -> (Int, [UInt8])? in
            guard let colon = line.firstIndex(of: ":"),
                  let sequence = Int(line[..<colon], radix: 16) else { return nil }
            return (sequence, bytes(in: String(line[line.index(after: colon)...])))
        }.sorted { $0.0 < $1.0 }
        guard ordered.first?.0 == 0 else { return nil }
        return decodeIdentifier(from: ordered.flatMap(\.1))
    }

    /// 責務: J1850等の行番号付き応答(`49 02 nn ...`)を順序バイトで並べ替えて復元します。
    private func parseLegacyFrames(_ lines: [String]) -> String? {
        let frames = lines.compactMap { line -> (Int, [UInt8])? in
            let values = bytes(in: line)
            guard values.count >= 4, values[0] == 0x49, values[1] == 0x02 else { return nil }
            return (Int(values[2]), Array(values.dropFirst(3)))
        }.sorted { $0.0 < $1.0 }
        if !frames.isEmpty { return decodeIdentifierPayload(frames.flatMap(\.1)) }
        return decodeIdentifier(from: lines.flatMap(bytes(in:)))
    }

    /// 責務: `49 02 01` 正応答の直後17バイトを識別子領域として取り出します。
    private func decodeIdentifier(from bytes: [UInt8]) -> String? {
        guard let start = bytes.indices.first(where: {
            $0 + 2 < bytes.count && bytes[$0] == 0x49 && bytes[$0 + 1] == 0x02 && bytes[$0 + 2] == 0x01
        }) else { return nil }
        return decodeIdentifierPayload(Array(bytes.dropFirst(start + 3)))
    }

    /// 責務: 17バイトの領域が表示可能ASCIIだけならVINとして返します(NUL/空白埋めは非VINとして拒否)。
    private func decodeIdentifierPayload(_ payload: [UInt8]) -> String? {
        let field = Array(payload.prefix(17))
        guard field.count == 17, field.allSatisfy({ (0x21...0x7E).contains($0) }) else { return nil }
        return String(bytes: field, encoding: .ascii)
    }

    /// 責務: 1行の16進文字列(空白あり/なし)から解釈可能なバイトを順序通り抽出します。
    private func bytes(in line: String) -> [UInt8] {
        let hex = line.filter(\.isHexDigit)
        guard hex.count.isMultiple(of: 2) else { return [] }
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            if let value = UInt8(hex[index..<end], radix: 16) { result.append(value) }
            index = end
        }
        return result
    }
}
