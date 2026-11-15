/// OBDアダプターが搭載する通信チップの系統です。
///
/// `rawValue` は取得証跡へ保存する安定文字列です。case名を変える場合は保存値を維持してください。
nonisolated enum OBDAdapterChipFamily: String, Equatable, Sendable {
    /// STN系チップ(OBDLink等)です。
    case stn
    /// 純正ELM327と判定したチップです。
    case elm327Genuine
    /// ELM327互換のクローンと判定したチップです。
    case elm327Clone
    /// 応答から系統を判定できなかったチップです。
    case unknown
}
