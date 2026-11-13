/// 取得時PID定義の式を再構築可能な値として固定します。
nonisolated struct AcquisitionPIDDefinitionIdentity: Equatable, Sendable {
    /// 式文字列の解釈規則を示す明示的な契約versionです。
    let canonicalizationVersion: Int
    /// 取得時定義に保存されていた制限付き式の完全な値です。
    let expression: String

    /// canonicalization契約と完全な式を固定します。
    ///
    /// 責務: digestへ意味を委ねずに取得時の変換式を再構築可能なidentityとして保持します。
    /// - Parameters:
    ///   - canonicalizationVersion: 式文字列の比較規則を示す正のversion。
    ///   - expression: 取得時定義に保存されていた空でない制限付き式。
    /// - Throws: versionが正でない場合または式が空の場合は `AcquisitionPIDDefinitionIdentityError.invalidValue`。
    init(canonicalizationVersion: Int, expression: String) throws {
        guard canonicalizationVersion > 0, !expression.isEmpty else {
            throw AcquisitionPIDDefinitionIdentityError.invalidValue
        }
        self.canonicalizationVersion = canonicalizationVersion
        self.expression = expression
    }
}

/// PID定義identityを確定できない理由です。
nonisolated enum AcquisitionPIDDefinitionIdentityError: Error, Equatable, Sendable {
    /// versionまたは式がidentityの前提を満たしません。
    case invalidValue
}
