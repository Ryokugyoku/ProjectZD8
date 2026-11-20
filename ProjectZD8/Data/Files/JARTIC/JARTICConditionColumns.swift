import Foundation

/// 対象1〜5と除外1〜5の条件の列番号を、見出しから一度だけ引いておく表です。
///
/// 1行ごとに90個の列名を組み立てて引き直さないために使います(東京都は約48万行)。
nonisolated struct JARTICConditionColumns: Sendable {
    /// 対象1〜5の組ごとの、項目から列番号への表(index 0 = 対象1)。見出しに無い項目は入りません。
    let targets: [[JARTICConditionField: Int]]
    /// 除外1〜5の組ごとの、項目から列番号への表(index 0 = 除外1)。見出しに無い項目は入りません。
    let exclusions: [[JARTICConditionField: Int]]

    /// 見出しから条件の列番号を引きます。
    ///
    /// 責務: 対象と除外の各組の9項目の列名を組み立て、列番号の表を作ります。
    /// - Parameter header: CSV の見出し。
    init(header: JARTICCSVHeader) {
        let sets = 1...JARTICColumnName.conditionSetCount
        targets = sets.map { set in Self.indices(in: header) { JARTICColumnName.target(set, $0) } }
        exclusions = sets.map { set in Self.indices(in: header) { JARTICColumnName.exclusion(set, $0) } }
    }

    /// 1つの組の9項目の列番号を引きます。
    ///
    /// 責務: 項目ごとに列名を作って見出しから列番号を引き、見つかった項目だけを表にします。
    /// - Parameters:
    ///   - header: CSV の見出し。
    ///   - name: 項目から列名を作る処理。
    /// - Returns: 項目から列番号への表。
    private static func indices(
        in header: JARTICCSVHeader,
        name: (JARTICConditionField) -> String
    ) -> [JARTICConditionField: Int] {
        var indices: [JARTICConditionField: Int] = [:]
        for field in JARTICConditionField.allCases {
            indices[field] = header.index(of: name(field))
        }
        return indices
    }
}
