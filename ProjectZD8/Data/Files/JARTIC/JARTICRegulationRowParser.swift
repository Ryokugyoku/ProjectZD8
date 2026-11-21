import Foundation

/// JARTIC の CSV の1行を、保存前の規制(`RoadRegulationDraft`)・読み飛ばし・理由つきの破棄のどれかに直す型です。
///
/// 設計書 §3.1 の規則を上から順に適用し、最初に当てはまった規則で結果を決めます(1〜13。14 は取り込み側)。
/// - 対象外の種別と廃止済みの行は `skipped`、必須項目の欠落や不正な値は `rejected` として、どちらも件数を数えられる値で返します。
/// - 時間・曜日・対象車両の条件は解釈せず、そのままの文字列で持ちます。
nonisolated struct JARTICRegulationRowParser: Sendable {
    /// 見出しの項目数(データ行の項目数と比べる)。
    private let fieldCount: Int
    /// 条件以外の列番号。
    private let columns: JARTICRegulationColumns
    /// 条件の列番号。
    private let conditionColumns: JARTICConditionColumns
    /// 形状を読む型。
    private let geometryReader: JARTICRegulationGeometryReader
    /// 条件を読む型。
    private let conditionParser = JARTICConditionSetParser()

    /// 見出しから、1行の解釈に使う列番号を引いておきます。
    ///
    /// 責務: 列名から列番号への変換を、行ごとでなく一度だけ行います。
    /// - Parameter header: CSV の見出し。
    init(header: JARTICCSVHeader) {
        let columns = JARTICRegulationColumns(header: header)
        fieldCount = header.fieldCount
        self.columns = columns
        conditionColumns = JARTICConditionColumns(header: header)
        geometryReader = JARTICRegulationGeometryReader(columns: columns)
    }

    /// 1行を解釈します。
    ///
    /// 責務: 規則を上から順に適用し、最初に止まった規則の結果か、保存前の規制を返します。
    /// - Parameter row: データの1行(見出しを除く)。
    /// - Returns: `regulation`・`skipped`・`rejected` のどれか。
    func parse(_ row: JARTICCSVRow) -> RoadRegulationArchiveRecord {
        do throws(JARTICRegulationRowStop) {
            return .regulation(try draft(from: row))
        } catch {
            return error.record
        }
    }

    /// 規則 1〜13 を順に適用して、保存前の規制を作ります。
    ///
    /// 責務: 各規則の判定を順に呼び、結果を1つの値にまとめます。
    /// - Parameter row: データの1行。
    /// - Returns: 保存前の規制。
    /// - Throws: 読み飛ばしか破棄に決まったら `JARTICRegulationRowStop`。
    private func draft(from row: JARTICCSVRow) throws(JARTICRegulationRowStop) -> RoadRegulationDraft {
        guard row.fieldCount == fieldCount else { throw .rejected(.fieldCountMismatch) }
        let kind = try kind(of: row)
        try requireNotAbolished(row)
        let uniqueKey = try uniqueKey(of: row)
        try requireShape(kind.expectedShape, of: row)
        let geometry = try geometryReader.geometry(of: row, kind: kind)
        let speedLimitKph = try speedLimit(of: row, kind: kind)
        let oneWayOrder = try oneWayOrder(of: row, kind: kind)
        return RoadRegulationDraft(
            uniqueKey: uniqueKey,
            kind: kind,
            speedLimitKph: speedLimitKph,
            side: integer(in: row, at: columns.side).flatMap(RoadRegulationSideCode.init(rawValue:)),
            oneWayOrder: oneWayOrder,
            perimeterRoadIncluded: perimeterRoadIncluded(of: row),
            conditions: conditionParser.conditions(from: row, columns: conditionColumns),
            geometry: geometry
        )
    }

    /// 共通規制種別コードを読みます(規則 2)。
    ///
    /// 責務: コードを整数として読み、対象の6種かを判定します。
    /// - Parameter row: データの1行。
    /// - Returns: 規制の種別。
    /// - Throws: 整数でなければ `missingRequiredField`、対象外なら `skipped(.outOfScopeKind)`。
    private func kind(of row: JARTICCSVRow) throws(JARTICRegulationRowStop) -> RoadRegulationKind {
        guard let code = integer(in: row, at: columns.kindCode) else { throw .rejected(.missingRequiredField) }
        guard let kind = RoadRegulationKind(commonCode: code) else { throw .skipped(.outOfScopeKind) }
        return kind
    }

    /// 廃止済みの行でないことを確かめます(規則 3)。
    ///
    /// 責務: 意思決定廃止日とデータ更新区分コード(3 = 廃止)を見ます。
    /// - Parameter row: データの1行。
    /// - Throws: 廃止日が空でないか、更新区分が `3` なら `skipped(.abolished)`。
    private func requireNotAbolished(_ row: JARTICCSVRow) throws(JARTICRegulationRowStop) {
        let isAbolished = !row.isBlank(columns.abolishedOn) || row.asciiString(columns.updateKind) == Self.abolishedUpdateKind
        guard !isAbolished else { throw .skipped(.abolished) }
    }

    /// ユニークキーを読みます(規則 4)。
    ///
    /// 責務: 空でない ASCII のキーを返します。
    /// - Parameter row: データの1行。
    /// - Returns: ユニークキー(前後の空白を除いたもの)。
    /// - Throws: 空か ASCII で読めなければ `missingRequiredField`。
    private func uniqueKey(of row: JARTICCSVRow) throws(JARTICRegulationRowStop) -> String {
        guard let key = row.asciiString(columns.uniqueKey), !key.isEmpty else { throw .rejected(.missingRequiredField) }
        return key
    }

    /// 点・線・面コードが種別の形状と一致することを確かめます(規則 5)。
    ///
    /// 責務: コードを形状に直して比べます。
    /// - Parameters:
    ///   - expected: 種別が期待する形状。
    ///   - row: データの1行。
    /// - Throws: 違う(空・未知のコードを含む)なら `shapeMismatch`。
    private func requireShape(_ expected: RoadRegulationShape, of row: JARTICCSVRow) throws(JARTICRegulationRowStop) {
        let shape = integer(in: row, at: columns.shapeCode).flatMap(RoadRegulationShape.init(rawValue:))
        guard shape == expected else { throw .rejected(.shapeMismatch) }
    }

    /// 最高速度を読みます(規則 10)。
    ///
    /// 責務: 最高速度(区間・区域)だけ 1〜120 の整数を求め、ほかの種別は読みません。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - kind: 規制の種別。
    /// - Returns: 最高速度(km/h)。可変区間とほかの種別は `nil`。
    /// - Throws: 最高速度(区間・区域)で 1〜120 の整数でなければ `invalidSpeed`。
    private func speedLimit(of row: JARTICCSVRow, kind: RoadRegulationKind) throws(JARTICRegulationRowStop) -> Int? {
        guard kind == .speedLimitSection || kind == .speedLimitZone else { return nil }
        guard let speed = integer(in: row, at: columns.speed), Self.speedLimitRange.contains(speed) else {
            throw .rejected(.invalidSpeed)
        }
        return speed
    }

    /// 一方通行の座標の並び順を読みます(規則 11)。
    ///
    /// 責務: 一方通行だけ、指定・禁止方向の別コードを求めます。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - kind: 規制の種別。
    /// - Returns: 並び順。一方通行以外は `nil`。
    /// - Throws: 一方通行でコードが `1` / `2` でなければ `invalidOneWayOrder`。
    private func oneWayOrder(of row: JARTICCSVRow, kind: RoadRegulationKind) throws(JARTICRegulationRowStop) -> RoadRegulationOneWayOrder? {
        guard kind == .oneWay else { return nil }
        guard let order = integer(in: row, at: columns.oneWayOrder).flatMap(RoadRegulationOneWayOrder.init(rawValue:)) else {
            throw .rejected(.invalidOneWayOrder)
        }
        return order
    }

    /// 面規制の外周道路有無コードを読みます(規則 12)。
    ///
    /// 責務: `1`(有)を true、`2`(無)を false に直します。
    /// - Parameter row: データの1行。
    /// - Returns: 外周道路を含むか。それ以外の値や空は `nil`。
    private func perimeterRoadIncluded(of row: JARTICCSVRow) -> Bool? {
        switch row.asciiString(columns.perimeterRoad) {
        case "1": true
        case "2": false
        default: nil
        }
    }

    /// 項目を10進の整数として読みます。
    ///
    /// 責務: ASCII の項目を前後の空白を除いて `Int` に直します。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - index: 列番号。
    /// - Returns: 整数。空・数字以外を含む・範囲外の列なら `nil`。
    private func integer(in row: JARTICCSVRow, at index: Int) -> Int? {
        guard let text = row.asciiString(index), !text.isEmpty, text.utf8.allSatisfy(Self.digitBytes.contains) else { return nil }
        return Int(text)
    }

    /// データ更新区分コードの「廃止」。
    private static let abolishedUpdateKind = "3"
    /// 最高速度として受け付ける範囲(km/h)。
    private static let speedLimitRange = 1...120
    /// ASCII の `0`〜`9`。
    private static let digitBytes = UInt8(ascii: "0")...UInt8(ascii: "9")
}
