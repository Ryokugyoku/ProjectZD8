/// 車両から読み取った文字列がVIN(ISO 3779)の書式を満たすかどうかを判定します。
nonisolated struct VehicleIdentificationNumberFormat: Sendable {
    /// VINの文字数です。
    static let length = 17
    /// VINで使える文字です(英大文字と数字。紛らわしい `I`・`O`・`Q` を除く)。
    private static let allowedCharacters = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")

    /// 文字列がVINの書式を満たすかどうかを判定します。
    ///
    /// 責務: 17文字で、使える文字だけで構成されている場合だけ妥当とします。チェックディジットは検証しません(地域により任意のため)。
    /// - Parameter candidate: 判定する文字列。
    /// - Returns: 妥当なら `true`。
    func isValid(_ candidate: String) -> Bool {
        candidate.count == Self.length && candidate.allSatisfy(Self.allowedCharacters.contains)
    }
}
