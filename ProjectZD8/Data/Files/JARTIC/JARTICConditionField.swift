import Foundation

/// JARTIC の CSV で、対象1〜5と除外1〜5の各組が持つ9つの条件の項目です。
///
/// 列名は `JARTICColumnName.target(_:_:)` と `JARTICColumnName.exclusion(_:_:)` で組み立てます。
nonisolated enum JARTICConditionField: CaseIterable, Sendable {
    /// 期間の開始(「対象期間N_開始」「除外期間N_開始」)。
    case periodStart
    /// 期間の終了(「対象期間N_終了」「除外期間N_終了」)。
    case periodEnd
    /// 時間の開始(「規制時間N_開始」「除外時間N_開始」)。
    case timeStart
    /// 時間の終了(「規制時間N_終了」「除外時間N_終了」)。
    case timeEnd
    /// 曜日コード(「規制曜日コードN」「除外曜日コードN」)。
    case day
    /// 車両コードのカテゴリ A(「対象車両コードN_A」「除外車両コードN_A」)。
    case vehicleA
    /// 車両コードのカテゴリ B。
    case vehicleB
    /// 車両コードのカテゴリ C。
    case vehicleC
    /// 車両コードのカテゴリ D。
    case vehicleD
}
