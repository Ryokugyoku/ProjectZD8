/// PID数値の取得時有効範囲を表します。
nonisolated struct AcquisitionPIDValidityRange: Equatable, Sendable {
    /// 有効範囲の下限です。`nil` は定義上の範囲なしを表します。
    let minimum: Double?
    /// 有効範囲の上限です。`nil` は定義上の範囲なしを表します。
    let maximum: Double?
    /// 定義上の有効範囲が明示されていないことを示す値です。
    static let notDeclared = AcquisitionPIDValidityRange(minimum: nil, maximum: nil)

    /// 有限かつ非減少の両端から有効範囲を生成します。
    ///
    /// 責務: PID定義の有効範囲を比較可能な閉区間へ固定します。
    /// - Parameters:
    ///   - minimum: 有効範囲に含める有限な下限。
    ///   - maximum: 有効範囲に含める有限な上限。
    /// - Returns: 両端を含む有効範囲。
    /// - Throws: 非有限値または下限が上限を超える場合は `AcquisitionPIDValidityRangeError.invalidBounds`。
    static func inclusive(minimum: Double, maximum: Double) throws -> Self {
        guard minimum.isFinite, maximum.isFinite, minimum <= maximum else {
            throw AcquisitionPIDValidityRangeError.invalidBounds
        }
        return AcquisitionPIDValidityRange(minimum: minimum, maximum: maximum)
    }

    /// 検証済みの両端または範囲なしを保持します。
    ///
    /// 責務: 有効範囲の内部表現を両端の組へ固定します。
    /// - Parameters:
    ///   - minimum: 検証済み下限、または範囲なしを示す `nil`。
    ///   - maximum: 検証済み上限、または範囲なしを示す `nil`。
    private init(minimum: Double?, maximum: Double?) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// PID有効範囲を確定できない理由です。
nonisolated enum AcquisitionPIDValidityRangeError: Error, Equatable, Sendable {
    /// 有効範囲の両端が有限な非減少区間ではありません。
    case invalidBounds
}
