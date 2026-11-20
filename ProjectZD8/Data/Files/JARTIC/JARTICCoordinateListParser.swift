import Foundation

/// JARTIC の CSV の座標の項目(「規制場所の経度緯度」「進入方向(座標)」「除外区間及び区域の経度緯度」)を読む型です。
///
/// 形は `"経度 緯度;経度 緯度/経度 緯度;…"` です(仕様書 3.1・NO.24)。
/// - `/` で区間(区域)に分け、`;` で点に分け、空白(1つ以上)で経度と緯度に分けます。**経度が先**です。
/// - 経度は 122〜154、緯度は 20〜46(両端を含む。日本の範囲)でなければ不正です。
/// - 区間の中で連続する同じ点は1つにまとめます。
/// - 空の区間・空の点(`;;`、末尾の `/` など)は不正として扱います(黙って読み飛ばしません)。
nonisolated struct JARTICCoordinateListParser: Sendable {
    /// 受け付ける緯度の範囲(度。両端を含む)。
    static let latitudeRange: ClosedRange<Double> = 20.0...46.0
    /// 受け付ける経度の範囲(度。両端を含む)。
    static let longitudeRange: ClosedRange<Double> = 122.0...154.0

    /// 座標の項目を区間ごとの点列にします。
    ///
    /// 責務: 項目全体を区間に分け、各区間を点列に直します。
    /// - Parameter field: 座標の項目のバイト列(ASCII)。
    /// - Returns: 区間ごとの点列。空(空白だけを含む)の項目は `[]`。数値でない・範囲外・空の区間や点があれば `nil`。
    func parse(_ field: ArraySlice<UInt8>) -> [[GeoCoordinate]]? {
        guard field.contains(where: { !Self.isWhitespace($0) }) else { return [] }
        var parts: [[GeoCoordinate]] = []
        for partBytes in field.split(separator: Self.partSeparator, omittingEmptySubsequences: false) {
            guard let part = parsePart(partBytes) else { return nil }
            parts.append(part)
        }
        return parts
    }

    /// 1つの区間を点列にします。
    ///
    /// 責務: 区間を点に分け、連続する同じ点を1つにまとめます。
    /// - Parameter bytes: 1つの区間のバイト列。
    /// - Returns: 点列。不正な点が1つでもあれば `nil`。
    private func parsePart(_ bytes: ArraySlice<UInt8>) -> [GeoCoordinate]? {
        var points: [GeoCoordinate] = []
        for pointBytes in bytes.split(separator: Self.pointSeparator, omittingEmptySubsequences: false) {
            guard let point = parsePoint(pointBytes) else { return nil }
            if points.last != point {
                points.append(point)
            }
        }
        return points
    }

    /// 1つの点(`経度 緯度`)を座標にします。
    ///
    /// 責務: 空白で2つの数値に分け、経度・緯度の順で読み、日本の範囲かを確かめます。
    /// - Parameter bytes: 1つの点のバイト列。
    /// - Returns: 座標。数値がちょうど2つでない・数値でない・範囲外なら `nil`。
    private func parsePoint(_ bytes: ArraySlice<UInt8>) -> GeoCoordinate? {
        let numbers = bytes.split(whereSeparator: Self.isWhitespace)
        guard numbers.count == 2,
              let longitude = Self.number(numbers[0]),
              let latitude = Self.number(numbers[1]),
              Self.longitudeRange.contains(longitude),
              Self.latitudeRange.contains(latitude) else { return nil }
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    /// 10進の数値を読みます。
    ///
    /// 責務: 数字・小数点・符号・指数の文字だけからなる時に `Double` へ直します(`nan`・`inf`・16進を受け付けません)。
    /// - Parameter bytes: 数値のバイト列。
    /// - Returns: 有限の値。読めなければ `nil`。
    private static func number(_ bytes: ArraySlice<UInt8>) -> Double? {
        guard !bytes.isEmpty, bytes.allSatisfy(isNumberByte) else { return nil }
        guard let value = Double(String(decoding: bytes, as: UTF8.self)), value.isFinite else { return nil }
        return value
    }

    /// 10進の数値に使える文字かを判定します。
    ///
    /// 責務: 数値として受け付ける文字の集合を1か所にまとめます。
    /// - Parameter byte: 判定するバイト。
    /// - Returns: `0`〜`9`・`.`・`+`・`-`・`e`・`E` なら `true`。
    private static func isNumberByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || numberSymbols.contains(byte)
    }

    /// 経度と緯度を分ける空白かを判定します。
    ///
    /// 責務: 区切りの空白(空白・タブ・CR・LF)の判定を1か所にまとめます。
    /// - Parameter byte: 判定するバイト。
    /// - Returns: 空白なら `true`。
    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }

    /// 区間(区域)の区切り `/`。
    private static let partSeparator = UInt8(ascii: "/")
    /// 点の区切り `;`。
    private static let pointSeparator = UInt8(ascii: ";")
    /// 数字以外で数値に使える文字(`.`・`+`・`-`・`e`・`E`)。
    private static let numberSymbols: Set<UInt8> = [
        UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "e"), UInt8(ascii: "E"),
    ]
}
