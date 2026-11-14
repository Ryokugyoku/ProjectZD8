/// アダプター識別コマンドの生応答と、そこから判定したチップ系統です。
nonisolated struct OBDAdapterIdentity: Equatable, Sendable {
    /// `ATZ`へ返った未加工応答です。
    let resetResponse: String
    /// `ATI`へ返った未加工応答です。
    let identityResponse: String
    /// `STI`へ返った未加工応答です。
    let stnIdentityResponse: String
    /// 生応答から判定したチップ系統です。
    let chipFamily: OBDAdapterChipFamily
}
