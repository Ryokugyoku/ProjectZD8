import Foundation

/// JARTIC の CSV の1行から、対象1〜5と除外1〜5の条件(期間・時間・曜日・車両の各コード)を読む型です。
///
/// 値は解釈せず、そのままの文字列で持ちます(解釈は `RoadRegulationApplicabilityEvaluator` の責務)。
/// ASCII で読めない値も捨てずに文字列で残します(空にすると「制約なし」と区別できなくなるため)。
nonisolated struct JARTICConditionSetParser: Sendable {
    /// 1行の条件を読みます。
    ///
    /// 責務: 見出しから条件の列番号を引き、各組の9項目を読みます。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - header: CSV の見出し。
    /// - Returns: 対象5組と除外5組の条件。
    func conditions(from row: JARTICCSVRow, header: JARTICCSVHeader) -> RoadRegulationConditions {
        conditions(from: row, columns: JARTICConditionColumns(header: header))
    }

    /// 引いておいた列番号を使って、1行の条件を読みます。
    ///
    /// 責務: 対象と除外の各組を `RoadRegulationConditionSet` に直します。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - columns: 見出しから引いておいた条件の列番号。
    /// - Returns: 対象5組と除外5組の条件。
    func conditions(from row: JARTICCSVRow, columns: JARTICConditionColumns) -> RoadRegulationConditions {
        RoadRegulationConditions(
            targets: columns.targets.map { conditionSet(from: row, indices: $0) },
            exclusions: columns.exclusions.map { conditionSet(from: row, indices: $0) }
        )
    }

    /// 1つの組の9項目を読みます。
    ///
    /// 責務: 項目ごとの列から値を読み、組の値にまとめます。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - indices: 項目から列番号への表。
    /// - Returns: 1組の条件。空の項目は `nil`。
    private func conditionSet(from row: JARTICCSVRow, indices: [JARTICConditionField: Int]) -> RoadRegulationConditionSet {
        let read: (JARTICConditionField) -> String? = { field in
            indices[field].flatMap { Self.value(in: row, at: $0) }
        }
        return RoadRegulationConditionSet(
            periodStart: read(.periodStart),
            periodEnd: read(.periodEnd),
            timeStart: read(.timeStart),
            timeEnd: read(.timeEnd),
            dayCode: read(.day),
            vehicleCodeA: read(.vehicleA),
            vehicleCodeB: read(.vehicleB),
            vehicleCodeC: read(.vehicleC),
            vehicleCodeD: read(.vehicleD)
        )
    }

    /// 1つの項目の値を文字列で読みます。
    ///
    /// 責務: ASCII ならそのまま、そうでなければ Shift-JIS で、それも無理なら置換文字つきで読みます(値を捨てません)。
    /// - Parameters:
    ///   - row: データの1行。
    ///   - index: 列番号。
    /// - Returns: 値。空か空白だけなら `nil`。
    private static func value(in row: JARTICCSVRow, at index: Int) -> String? {
        guard !row.isBlank(index) else { return nil }
        if let ascii = row.asciiString(index) {
            return ascii
        }
        let bytes = row.field(index)
        return String(bytes: bytes, encoding: .shiftJIS) ?? String(decoding: bytes, as: UTF8.self)
    }
}
