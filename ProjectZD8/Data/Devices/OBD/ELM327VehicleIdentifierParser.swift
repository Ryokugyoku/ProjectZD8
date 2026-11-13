import Foundation

/// ELM/STNが整形したService 09 PID 02応答から車両識別子を復元します。
struct ELM327VehicleIdentifierParser {
    /// VINと非VINのOBD由来識別子を分離した解析結果です。
    struct Result: Equatable {
        /// 17バイトの表示可能文字として取得できたVIN候補です。
        let vin: String?
        /// 空白またはNULL埋めを除いた非VINのOBD由来識別子です。
        let obdIdentifier: String?
    }

    /// 複数プロトコル形式を保った応答から車両識別子を取り出します。
    ///
    /// 責務: 1件のMode 09応答をVINまたは非VINのOBD由来識別子へ復元します。
    /// - Parameter response: プロンプトを除いた加工前ELM/STN応答。
    /// - Returns: VINと非VIN識別子を混同しない解析結果。
    /// - Throws: 正応答、順序、またはASCII識別子を確認できない場合は `VehicleIdentificationError.malformedResponse`。
    func parse(_ response: String) throws -> Result {
        let lines = response
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "\r") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("SEARCHING") }
        if let identifier = parseCANFormatted(lines) ?? parseLegacyFrames(lines) { return identifier }
        throw VehicleIdentificationError.malformedResponse
    }

    /// CAN自動整形済みの連続行を解析します。
    ///
    /// 責務: CAN連続フレームの表示順序からMode 09ペイロードを連結します。
    /// - Parameter lines: 空行を除いた応答行。
    /// - Returns: 復元できた識別子。対象形式でなければ `nil`。
    private func parseCANFormatted(_ lines: [String]) -> Result? {
        let ordered = lines.compactMap { line -> (Int, [UInt8])? in
            guard let colon = line.firstIndex(of: ":"),
                  let sequence = Int(line[..<colon], radix: 16) else { return nil }
            return (sequence, bytes(in: String(line[line.index(after: colon)...])))
        }.sorted { $0.0 < $1.0 }
        guard ordered.first?.0 == 0 else { return nil }
        return decodeIdentifier(from: ordered.flatMap(\.1))
    }

    /// J1850等の行番号付きMode 09応答を解析します。
    ///
    /// 責務: 各行の49 02応答と順序バイトから識別子領域を並べ替えます。
    /// - Parameter lines: 空行を除いた応答行。
    /// - Returns: 復元できた識別子。対象形式でなければ `nil`。
    private func parseLegacyFrames(_ lines: [String]) -> Result? {
        let frames = lines.compactMap { line -> (Int, [UInt8])? in
            let values = bytes(in: line)
            guard values.count >= 4, values[0] == 0x49, values[1] == 0x02 else { return nil }
            return (Int(values[2]), Array(values.dropFirst(3)))
        }.sorted { $0.0 < $1.0 }
        if !frames.isEmpty { return decodeIdentifierPayload(frames.flatMap(\.1)) }
        return decodeIdentifier(from: lines.flatMap(bytes(in:)))
    }

    /// Service/PID/項目数を含む連結ペイロードから識別子領域を取り出します。
    ///
    /// 責務: 49 02 01正応答の直後17バイトだけを識別子候補へ渡します。
    /// - Parameter bytes: 連結された応答データ。
    /// - Returns: 正応答から復元できた識別子。
    private func decodeIdentifier(from bytes: [UInt8]) -> Result? {
        guard let start = bytes.indices.first(where: {
            $0 + 2 < bytes.count && bytes[$0] == 0x49 && bytes[$0 + 1] == 0x02 && bytes[$0 + 2] == 0x01
        }) else { return nil }
        return decodeIdentifierPayload(Array(bytes.dropFirst(start + 3)))
    }

    /// 17バイトの識別子領域をVINまたは非VIN識別子に分類します。
    ///
    /// 責務: 文字埋めの有無だけでVIN候補と非VINのOBD由来識別子を分離します。
    /// - Parameter payload: Service/PID/項目数を除いたデータ。
    /// - Returns: ASCIIとして復元できた識別子。形式不正なら `nil`。
    private func decodeIdentifierPayload(_ payload: [UInt8]) -> Result? {
        let field = Array(payload.prefix(17))
        guard field.count == 17 else { return nil }
        if field.allSatisfy({ (0x21...0x7E).contains($0) }),
           let vin = String(bytes: field, encoding: .ascii) {
            return Result(vin: vin, obdIdentifier: nil)
        }
        let trimmed = field
            .drop(while: { $0 == 0x00 || $0 == 0x20 })
            .reversed()
            .drop(while: { $0 == 0x00 || $0 == 0x20 })
            .reversed()
        guard !trimmed.isEmpty, trimmed.allSatisfy({ (0x21...0x7E).contains($0) }),
              let identifier = String(bytes: trimmed, encoding: .ascii) else { return nil }
        return Result(vin: nil, obdIdentifier: identifier)
    }

    /// 行内の16進数2桁トークンをバイトへ変換します。
    ///
    /// 責務: 1件のELM表示行から解釈可能な16進バイトだけを順序通り抽出します。
    /// - Parameter line: 空白ありまたは連続16進形式の行。
    /// - Returns: 抽出できたバイト列。
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
