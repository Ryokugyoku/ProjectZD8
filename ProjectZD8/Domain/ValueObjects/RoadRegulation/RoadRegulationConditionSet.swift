import Foundation

/// 規制の対象または除外の1組を、JARTIC の生のコード文字列のまま表します。
///
/// 各項目は前後の空白を除いた値で、空なら `nil` です。解釈は判定の時に行います。
nonisolated struct RoadRegulationConditionSet: Codable, Equatable, Sendable {
    /// 項目がすべて空の組です。
    static let empty = RoadRegulationConditionSet()

    /// 期間の開始(MMDD)。
    let periodStart: String?
    /// 期間の終了(MMDD)。
    let periodEnd: String?
    /// 時間の開始(hhmm、先頭0なし)。
    let timeStart: String?
    /// 時間の終了(hhmm、先頭0なし)。
    let timeEnd: String?
    /// 曜日コード。
    let dayCode: String?
    /// 対象車両コード(カテゴリ A)。
    let vehicleCodeA: String?
    /// 対象車両コード(カテゴリ B)。
    let vehicleCodeB: String?
    /// 対象車両コード(カテゴリ C)。
    let vehicleCodeC: String?
    /// 対象車両コード(カテゴリ D)。
    let vehicleCodeD: String?

    /// 生のコード文字列から1組を作ります。
    ///
    /// 責務: 各項目の前後の空白を除き、空になった項目を `nil` に揃えます。
    /// - Parameters:
    ///   - periodStart: 期間の開始。
    ///   - periodEnd: 期間の終了。
    ///   - timeStart: 時間の開始。
    ///   - timeEnd: 時間の終了。
    ///   - dayCode: 曜日コード。
    ///   - vehicleCodeA: 車両コード A。
    ///   - vehicleCodeB: 車両コード B。
    ///   - vehicleCodeC: 車両コード C。
    ///   - vehicleCodeD: 車両コード D。
    init(
        periodStart: String? = nil,
        periodEnd: String? = nil,
        timeStart: String? = nil,
        timeEnd: String? = nil,
        dayCode: String? = nil,
        vehicleCodeA: String? = nil,
        vehicleCodeB: String? = nil,
        vehicleCodeC: String? = nil,
        vehicleCodeD: String? = nil
    ) {
        self.periodStart = Self.normalized(periodStart)
        self.periodEnd = Self.normalized(periodEnd)
        self.timeStart = Self.normalized(timeStart)
        self.timeEnd = Self.normalized(timeEnd)
        self.dayCode = Self.normalized(dayCode)
        self.vehicleCodeA = Self.normalized(vehicleCodeA)
        self.vehicleCodeB = Self.normalized(vehicleCodeB)
        self.vehicleCodeC = Self.normalized(vehicleCodeC)
        self.vehicleCodeD = Self.normalized(vehicleCodeD)
    }

    /// すべての項目が空かどうかです。
    var isEmpty: Bool {
        allFields.allSatisfy { $0 == nil }
    }

    /// 9項目を宣言順に並べた配列です。
    private var allFields: [String?] {
        [periodStart, periodEnd, timeStart, timeEnd, dayCode, vehicleCodeA, vehicleCodeB, vehicleCodeC, vehicleCodeD]
    }

    /// 1項目の値を揃えます。
    ///
    /// 責務: 前後の空白と改行を除き、空なら `nil` にします。
    /// - Parameter value: 生の値。
    /// - Returns: 揃えた値。
    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
