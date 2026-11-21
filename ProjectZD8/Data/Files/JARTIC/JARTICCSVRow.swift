import Foundation

/// JARTIC の CSV の1行を、Shift-JIS のバイト列のまま項目に区切った値です。
///
/// 全項目の中身(引用符を外し `""` を `"` にした後)を `bytes` に連続して持ち、各項目の終わりの位置を `fieldEnds` に持ちます。
/// 項目 i は `fieldEnds[i - 1]..<fieldEnds[i]`(i = 0 は `0..<fieldEnds[0]`)です。
/// 文字列への復号は、必要な項目だけに後から行います。
nonisolated struct JARTICCSVRow: Equatable, Sendable {
    /// 全項目の中身を連結したバイト列。
    let bytes: [UInt8]
    /// 各項目の終わりの位置(`bytes` の添字。単調非減少)。
    let fieldEnds: [Int]

    /// 連結したバイト列と、各項目の終わりの位置から行を作ります。
    ///
    /// 責務: 区切り済みの1行を保持します。
    /// - Parameters:
    ///   - bytes: 全項目の中身を連結したバイト列。
    ///   - fieldEnds: 各項目の終わりの位置。
    init(bytes: [UInt8], fieldEnds: [Int]) {
        self.bytes = bytes
        self.fieldEnds = fieldEnds
    }

    /// 項目の数。
    var fieldCount: Int {
        fieldEnds.count
    }

    /// 指定した項目のバイト列を返します。
    ///
    /// 責務: 項目の範囲を切り出します(複製しません)。
    /// - Parameter index: 0 始まりの項目の位置。
    /// - Returns: 項目のバイト列。範囲外や壊れた位置なら空。
    func field(_ index: Int) -> ArraySlice<UInt8> {
        guard let range = range(of: index) else { return bytes[0..<0] }
        return bytes[range]
    }

    /// 指定した項目を、前後の空白を除いた ASCII の文字列として返します。
    ///
    /// 責務: コード・座標・速度などの ASCII の値を、Shift-JIS の復号なしで読みます。
    /// - Parameter index: 0 始まりの項目の位置。
    /// - Returns: 前後の空白(空白・タブ・CR・LF)を除いた文字列。ASCII 以外を含むか範囲外なら `nil`。
    func asciiString(_ index: Int) -> String? {
        guard range(of: index) != nil else { return nil }
        let value = field(index)
        guard value.allSatisfy({ $0 < 0x80 }) else { return nil }
        guard let first = value.firstIndex(where: { !Self.isASCIIWhitespace($0) }),
              let last = value.lastIndex(where: { !Self.isASCIIWhitespace($0) }) else { return "" }
        return String(decoding: value[first...last], as: UTF8.self)
    }

    /// 指定した項目が空か、空白だけかを判定します。
    ///
    /// 責務: 値の有無を、復号せずに判定します。
    /// - Parameter index: 0 始まりの項目の位置。
    /// - Returns: 空・ASCII の空白だけ・範囲外なら `true`。
    func isBlank(_ index: Int) -> Bool {
        field(index).allSatisfy(Self.isASCIIWhitespace)
    }

    /// 指定した項目の `bytes` 上の範囲を求めます。
    ///
    /// 責務: 項目の位置と終わりの位置の整合を確かめます。
    /// - Parameter index: 0 始まりの項目の位置。
    /// - Returns: 範囲。範囲外や壊れた位置なら `nil`。
    private func range(of index: Int) -> Range<Int>? {
        guard fieldEnds.indices.contains(index) else { return nil }
        let start = index == 0 ? 0 : fieldEnds[index - 1]
        let end = fieldEnds[index]
        guard start >= 0, start <= end, end <= bytes.count else { return nil }
        return start..<end
    }

    /// ASCII の空白(空白・タブ・CR・LF)かを判定します。
    ///
    /// 責務: 前後の空白を除く時の判定を1か所にまとめます。
    /// - Parameter byte: 判定するバイト。
    /// - Returns: 空白なら `true`。
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }
}
