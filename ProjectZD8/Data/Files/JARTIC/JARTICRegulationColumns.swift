import Foundation

/// 1行の解釈に使う、条件以外の列の番号を見出しから一度だけ引いておく表です。
///
/// `JARTICCSVHeader` は必須の列がそろわなければ作れないので、通常はすべて見つかります。
/// 見つからない列は `missing`(-1)にし、その列は空として読まれます(`JARTICCSVRow` は範囲外を空として返すため)。
nonisolated struct JARTICRegulationColumns: Sendable {
    /// 見出しに無い列の番号。
    static let missing = -1

    /// 共通規制種別コード。
    let kindCode: Int
    /// 点・線・面コード。
    let shapeCode: Int
    /// 意思決定廃止日。
    let abolishedOn: Int
    /// データ更新区分コード。
    let updateKind: Int
    /// ユニークキー。
    let uniqueKey: Int
    /// 規制場所の経度緯度。
    let coordinates: Int
    /// 除外区間及び区域の経度緯度。
    let exclusionCoordinates: Int
    /// 面規制の外周道路有無コード。
    let perimeterRoad: Int
    /// 進入方向(座標)。
    let approachCoordinates: Int
    /// 指定・禁止方向の別コード。
    let oneWayOrder: Int
    /// 片側・両側コード。
    let side: Int
    /// 速度。
    let speed: Int

    /// 見出しから列番号を引きます。
    ///
    /// 責務: 解釈に使う列の名前を列番号に直します。
    /// - Parameter header: CSV の見出し。
    init(header: JARTICCSVHeader) {
        let index: (String) -> Int = { header.index(of: $0) ?? Self.missing }
        kindCode = index(JARTICColumnName.kindCode)
        shapeCode = index(JARTICColumnName.shapeCode)
        abolishedOn = index(JARTICColumnName.abolishedOn)
        updateKind = index(JARTICColumnName.updateKind)
        uniqueKey = index(JARTICColumnName.uniqueKey)
        coordinates = index(JARTICColumnName.coordinates)
        exclusionCoordinates = index(JARTICColumnName.exclusionCoordinates)
        perimeterRoad = index(JARTICColumnName.perimeterRoad)
        approachCoordinates = index(JARTICColumnName.approachCoordinates)
        oneWayOrder = index(JARTICColumnName.oneWayOrder)
        side = index(JARTICColumnName.side)
        speed = index(JARTICColumnName.speed)
    }
}
