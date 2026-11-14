import Foundation

/// `ATH1`・`ATS1`設定時の`ATMA`受信監視の1行をCANフレームへ変換します。
nonisolated struct ELM327CANFrameParser: Sendable {
    /// CANフレームが持てる最大データ長です。
    private static let maximumPayloadLength = 8
    /// 2桁区切りの29bit IDを構成するトークン数です。
    private static let splitExtendedIdentifierTokenCount = 4

    /// 1行をCANフレームへ変換します。
    ///
    /// 責務: プロンプト除去・trim・空白分割の後、先頭トークンの桁数でIDを決め、残りをデータバイトとして検証します。
    /// - Parameter line: 受信監視で届いた1行。
    /// - Returns: 復元したフレーム、または解釈できなかった理由。
    func parse(_ line: String) -> Result<ELM327CANFrame, ELM327CANFrameParseError> {
        let tokens = line.replacingOccurrences(of: ">", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return .failure(.emptyLine) }
        let identifier: (value: UInt32, isExtended: Bool, tokenCount: Int)
        switch Self.parseIdentifier(tokens) {
        case .success(let parsed): identifier = parsed
        case .failure(let error): return .failure(error)
        }
        return Self.parsePayload(tokens.dropFirst(identifier.tokenCount)).map {
            ELM327CANFrame(canIdentifier: identifier.value, isExtended: identifier.isExtended, payload: $0)
        }
    }

    /// 先頭トークンの桁数からCAN IDを決めます。
    ///
    /// 責務: 3桁を11bit、8桁を29bit、2桁を先頭4トークン連結の29bitとして解釈し、範囲外や形式外を失敗にします。
    /// - Parameter tokens: 空でないトークン列。
    /// - Returns: ID値、拡張IDかどうか、IDが消費したトークン数。
    private static func parseIdentifier(
        _ tokens: [String]
    ) -> Result<(value: UInt32, isExtended: Bool, tokenCount: Int), ELM327CANFrameParseError> {
        let head = tokens[0]
        guard let headValue = hexadecimalValue(head) else { return .failure(.invalidIdentifier) }
        switch head.count {
        case 3:
            guard headValue <= 0x7FF else { return .failure(.identifierOutOfRange) }
            return .success((headValue, false, 1))
        case 8:
            guard headValue <= 0x1FFF_FFFF else { return .failure(.identifierOutOfRange) }
            return .success((headValue, true, 1))
        case 2:
            return parseSplitExtendedIdentifier(tokens).map { ($0, true, splitExtendedIdentifierTokenCount) }
        default:
            return .failure(.invalidIdentifier)
        }
    }

    /// 2桁ずつ区切られた先頭4トークンを29bit IDへ連結します。
    ///
    /// 責務: 4トークン未満を`missingIdentifier`、2桁16進でないトークンを`invalidIdentifier`、範囲外を`identifierOutOfRange`にします。
    /// - Parameter tokens: 先頭が2桁のトークン列。
    /// - Returns: 連結したID値。
    private static func parseSplitExtendedIdentifier(_ tokens: [String]) -> Result<UInt32, ELM327CANFrameParseError> {
        guard tokens.count >= splitExtendedIdentifierTokenCount else { return .failure(.missingIdentifier) }
        var value: UInt32 = 0
        for token in tokens.prefix(splitExtendedIdentifierTokenCount) {
            guard token.count == 2, let byte = hexadecimalValue(token) else { return .failure(.invalidIdentifier) }
            value = (value << 8) | byte
        }
        guard value <= 0x1FFF_FFFF else { return .failure(.identifierOutOfRange) }
        return .success(value)
    }

    /// ID以降のトークンをデータバイト列へ変換します。
    ///
    /// 責務: 9バイト以上を`payloadTooLong`、2桁でないトークンを`malformedByte`、非16進を`nonHexadecimalByte`にします。
    /// - Parameter tokens: ID以降のトークン列。
    /// - Returns: 0〜8バイトのデータ。
    private static func parsePayload(_ tokens: ArraySlice<String>) -> Result<[UInt8], ELM327CANFrameParseError> {
        guard tokens.count <= maximumPayloadLength else { return .failure(.payloadTooLong) }
        var payload: [UInt8] = []
        for token in tokens {
            guard token.count == 2 else { return .failure(.malformedByte) }
            guard let byte = hexadecimalValue(token) else { return .failure(.nonHexadecimalByte) }
            payload.append(UInt8(byte))
        }
        return .success(payload)
    }

    /// ASCII 16進数字だけからなるトークンを数値へ変換します。
    ///
    /// 責務: 符号や全角数字を拒否し、大文字小文字の16進数字だけを受理します。
    /// - Parameter token: 変換するトークン。
    /// - Returns: 数値。16進以外の文字を含むか、`UInt32`を超える場合はnil。
    private static func hexadecimalValue(_ token: String) -> UInt32? {
        guard !token.isEmpty, token.unicodeScalars.allSatisfy({ isASCIIHexDigit($0) }) else { return nil }
        return UInt32(token, radix: 16)
    }

    /// 1文字がASCIIの16進数字かどうかを判定します。
    ///
    /// 責務: `0-9`・`A-F`・`a-f`だけを16進数字として扱います。
    /// - Parameter scalar: 判定する文字。
    /// - Returns: ASCII 16進数字ならtrue。
    private static func isASCIIHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "0"..."9", "A"..."F", "a"..."f": true
        default: false
        }
    }
}
