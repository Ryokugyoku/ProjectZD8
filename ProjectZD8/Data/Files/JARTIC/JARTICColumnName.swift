import Foundation

/// JARTIC の CSV(拡張版標準フォーマット)の見出しにある列名(Shift-JIS を復号した後)です。
///
/// 列は位置でなく名前で引きます(列の順序が変わっても動くように)。括弧と `_` は半角です。
nonisolated enum JARTICColumnName {
    /// 版(例 `k_2.1`)。
    static let formatVersion = "拡張版標準フォーマット種別・バージョン"
    /// 共通規制種別コード。
    static let kindCode = "共通規制種別コード"
    /// 点・線・面コード。
    static let shapeCode = "点・線・面コード"
    /// 意思決定廃止日。
    static let abolishedOn = "意思決定廃止日"
    /// データ更新区分コード。
    static let updateKind = "データ更新区分コード"
    /// ユニークキー。
    static let uniqueKey = "ユニークキー"
    /// 規制場所の経度緯度。
    static let coordinates = "規制場所の経度緯度"
    /// 除外区間及び区域の経度緯度。
    static let exclusionCoordinates = "除外区間及び区域の経度緯度"
    /// 面規制の外周道路有無コード。
    static let perimeterRoad = "面規制の外周道路有無コード"
    /// 進入方向(座標)。括弧は半角です。
    static let approachCoordinates = "進入方向(座標)"
    /// 指定・禁止方向の別コード。
    static let oneWayOrder = "指定・禁止方向の別コード"
    /// 片側・両側コード。
    static let side = "片側・両側コード"
    /// 速度。
    static let speed = "速度"

    /// 対象の組の列名を返します。
    ///
    /// 責務: 「対象期間N_開始」「規制時間N_終了」「規制曜日コードN」「対象車両コードN_A」などを組み立てます。
    /// - Parameters:
    ///   - set: 組の番号(1〜5)。
    ///   - field: 条件の項目。
    /// - Returns: 列名。
    static func target(_ set: Int, _ field: JARTICConditionField) -> String {
        conditionName(set, field, labels: .target)
    }

    /// 除外の組の列名を返します。
    ///
    /// 責務: 「除外期間N_開始」「除外時間N_終了」「除外曜日コードN」「除外車両コードN_A」などを組み立てます。
    /// - Parameters:
    ///   - set: 組の番号(1〜5)。
    ///   - field: 条件の項目。
    /// - Returns: 列名。
    static func exclusion(_ set: Int, _ field: JARTICConditionField) -> String {
        conditionName(set, field, labels: .exclusion)
    }

    /// 取り込みに必須の列名(単独の13個と、対象・除外の各5組×9項目の90個で、計103個)。
    static var required: [String] {
        let single = [
            formatVersion, kindCode, shapeCode, abolishedOn, updateKind, uniqueKey, coordinates,
            exclusionCoordinates, perimeterRoad, approachCoordinates, oneWayOrder, side, speed,
        ]
        let sets = 1...conditionSetCount
        let targets = sets.flatMap { set in JARTICConditionField.allCases.map { target(set, $0) } }
        let exclusions = sets.flatMap { set in JARTICConditionField.allCases.map { exclusion(set, $0) } }
        return single + targets + exclusions
    }

    /// 対象と除外のそれぞれの組の数。
    static let conditionSetCount = 5

    /// 条件の列名の、対象と除外で異なる部分です。
    private struct ConditionLabels {
        /// 期間の語(「対象期間」「除外期間」)。
        let period: String
        /// 時間の語(「規制時間」「除外時間」)。
        let time: String
        /// 曜日コードの語(「規制曜日コード」「除外曜日コード」)。
        let day: String
        /// 車両コードの語(「対象車両コード」「除外車両コード」)。
        let vehicle: String

        /// 対象の組の語。
        static let target = ConditionLabels(period: "対象期間", time: "規制時間", day: "規制曜日コード", vehicle: "対象車両コード")
        /// 除外の組の語。
        static let exclusion = ConditionLabels(period: "除外期間", time: "除外時間", day: "除外曜日コード", vehicle: "除外車両コード")
    }

    /// 条件の列名を組み立てます。
    ///
    /// 責務: 項目の種類ごとに、語・組の番号・接尾辞を並べます。
    /// - Parameters:
    ///   - set: 組の番号。
    ///   - field: 条件の項目。
    ///   - labels: 対象か除外かの語。
    /// - Returns: 列名。
    private static func conditionName(_ set: Int, _ field: JARTICConditionField, labels: ConditionLabels) -> String {
        switch field {
        case .periodStart: "\(labels.period)\(set)_開始"
        case .periodEnd: "\(labels.period)\(set)_終了"
        case .timeStart: "\(labels.time)\(set)_開始"
        case .timeEnd: "\(labels.time)\(set)_終了"
        case .day: "\(labels.day)\(set)"
        case .vehicleA, .vehicleB, .vehicleC, .vehicleD: "\(labels.vehicle)\(set)_\(vehicleCategory(field))"
        }
    }

    /// 車両コードの項目のカテゴリの文字を返します。
    ///
    /// 責務: 車両コードの項目を A〜D の文字へ写します。
    /// - Parameter field: 車両コードの項目。
    /// - Returns: `A`〜`D`。車両コード以外の項目は空文字。
    private static func vehicleCategory(_ field: JARTICConditionField) -> String {
        switch field {
        case .vehicleA: "A"
        case .vehicleB: "B"
        case .vehicleC: "C"
        case .vehicleD: "D"
        default: ""
        }
    }
}
