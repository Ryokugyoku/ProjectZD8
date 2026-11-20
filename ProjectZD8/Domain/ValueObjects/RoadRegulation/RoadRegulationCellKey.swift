import Foundation

/// 交通規制の検索に使う升目(2分の1地域メッシュと同じ刻み)の鍵です。`rawValue = row × 65,536 + column`。
nonisolated struct RoadRegulationCellKey: Hashable, Comparable, Sendable {
    /// 行と列を1つの値へ詰める時の列の幅です。
    static let columnStride: Int64 = 65_536

    /// DB に保存する鍵の値です。
    let rawValue: Int64

    /// 行と列から鍵を作ります。
    ///
    /// 責務: `row × 65,536 + column` を計算します。列は 0..<65,536 であることを前提にします。
    /// - Parameters:
    ///   - row: 緯度方向の升目番号(`floor((lat + 90) × 240)`)。
    ///   - column: 経度方向の升目番号(`floor((lon + 180) × 160)`)。
    init(row: Int, column: Int) {
        self.rawValue = Int64(row) * Self.columnStride + Int64(column)
    }

    /// 緯度方向の升目番号です。
    var row: Int {
        Int(rawValue >> 16)
    }

    /// 経度方向の升目番号です。
    var column: Int {
        Int(rawValue & (Self.columnStride - 1))
    }

    /// 鍵の値の昇順で比べます。
    ///
    /// 責務: 升目の安定した並び順を決めます。
    /// - Parameters:
    ///   - lhs: 左辺。
    ///   - rhs: 右辺。
    /// - Returns: 左辺の値が小さければ `true`。
    static func < (lhs: RoadRegulationCellKey, rhs: RoadRegulationCellKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
