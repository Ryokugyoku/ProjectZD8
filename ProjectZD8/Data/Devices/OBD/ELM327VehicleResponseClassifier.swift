import Foundation

/// 標準PID `0100` への加工前応答を、ECUが応答したかどうかへ分類します。
///
/// 正応答(サービス `41`・PID `00` のバイト列)を含む場合だけ応答ありとします。ヘッダー(11bit・29bit)の有無、空白の有無、
/// 大文字小文字、改行コードの違いで結果は変わりません(区切り方は `hexadecimalBytes(_:)` の境界条件を参照)。
///
/// `NO DATA`・`UNABLE TO CONNECT`・`SEARCHING...` のみ・`BUS ERROR`/`CAN ERROR` 等・`?`・空応答はすべて無応答とします。
nonisolated struct ELM327VehicleResponseClassifier: Sendable {
    /// 正応答のサービスバイトです。
    private static let positiveServiceByte: UInt8 = 0x41
    /// 問い合わせたPIDです。
    private static let requestedPID: UInt8 = 0x00

    /// 応答をECU応答の有無へ分類します。
    ///
    /// 責務: 16進だけで構成された行に `41 00` の並びがあるかどうかで応答の有無を決めます。
    /// - Parameter response: `0100` の加工前応答。
    /// - Returns: 正応答を含めば `.responding`、それ以外は `.noResponse`。
    func classify(_ response: String) -> VehicleResponseOutcome {
        let containsPositiveResponse = ELM327ResponseLines.normalizedLines(of: response)
            .compactMap(Self.hexadecimalBytes)
            .contains(where: Self.containsPositiveResponse)
        return containsPositiveResponse ? .responding : .noResponse
    }

    /// バイト列に `41 00` の並びがあるかどうかを判定します。
    ///
    /// 責務: ヘッダー表示の有無にかかわらず、隣り合う2バイトで正応答の先頭を探します。
    /// - Parameter bytes: 1行分のバイト列。
    /// - Returns: 並びがあれば `true`。
    private static func containsPositiveResponse(_ bytes: [UInt8]) -> Bool {
        zip(bytes, bytes.dropFirst()).contains { $0 == positiveServiceByte && $1 == requestedPID }
    }

    /// 11bit CAN ID ヘッダー(`ATH1` 時の `7E8` など)の16進桁数です。
    private static let elevenBitHeaderDigitCount = 3

    /// 16進だけで構成された行をバイト列へ変換します。
    ///
    /// 責務: 空白区切りと連続表記の両方を受け付け、16進以外の文字を含む行を除外し、バイト境界に沿って2桁ずつ区切ります。
    /// 境界条件:
    /// - 空白区切りの行: 奇数桁のトークン(11bit CAN ID `7E8` など)はバイトに含めず、偶数桁のトークンを先頭から2桁ずつ区切ります。
    /// - 空白なしで偶数桁の行: 先頭から2桁ずつ区切ります(ヘッダーなし、または29bit CAN ID `18DAF110` の8桁ヘッダー付き)。
    /// - 空白なしで奇数桁の行: 先頭3桁を11bit CAN ID とみなして除き、残りを2桁ずつ区切ります(`7E806410098180001` → `06 41 00 …`)。
    ///   3桁に満たない行はバイトなしとします。
    /// いずれも区切りはバイト境界に固定するので、2バイトにまたがって現れるだけの `4 10 0` は `41 00` と見なしません。
    /// - Parameter line: 正規化済みの1行。
    /// - Returns: バイト列。16進の行でなければ `nil`。
    private static func hexadecimalBytes(_ line: String) -> [UInt8]? {
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty, tokens.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) else { return nil }
        if tokens.count == 1, let token = tokens.first, !token.count.isMultiple(of: 2) {
            guard token.count >= elevenBitHeaderDigitCount else { return [] }
            return bytes(token.dropFirst(elevenBitHeaderDigitCount))
        }
        return tokens.filter { $0.count.isMultiple(of: 2) }.flatMap(Self.bytes)
    }

    /// 偶数桁の16進トークンを2桁ずつバイトへ変換します。
    ///
    /// 責務: 1件のトークンを先頭から順にバイト列へ変換します。
    /// - Parameter token: 偶数桁の16進トークン。
    /// - Returns: バイト列。
    private static func bytes(_ token: Substring) -> [UInt8] {
        stride(from: 0, to: token.count, by: 2).compactMap { offset in
            let start = token.index(token.startIndex, offsetBy: offset)
            return UInt8(token[start..<token.index(start, offsetBy: 2)], radix: 16)
        }
    }
}
