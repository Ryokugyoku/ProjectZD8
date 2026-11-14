import Foundation

/// `STI`/`ATI`の生応答からアダプターのチップ系統を判定します。
///
/// `ELM327 v1.5`以外のバージョンを名乗るELM327は純正とクローンを応答だけで区別できないため、追加プローブの結果で判定します。
/// 追加プローブには仮に`ATPPS`を使う想定で、純正とクローンで応答が分かれることは実機では未確認です。
nonisolated struct OBDAdapterChipClassificationPolicy: Sendable {
    /// エコーとして捨てる送信コマンドです(大文字で比較)。
    private static let echoCommands: Set<String> = ["STI", "ATI"]
    /// ELM327識別文字列の接頭辞です(大文字で比較)。
    private static let elm327VersionPrefix = "ELM327 V"
    /// 多くのクローンが名乗るELM327のバージョンです。
    private static let cloneVersion = "1.5"

    /// 識別応答からチップ系統を判定します。
    ///
    /// 責務: STN応答、ELM327のバージョン、追加プローブ結果の順に評価し、判定できない応答を`unknown`にします。
    /// - Parameters:
    ///   - stnIdentityResponse: `STI`の生応答。
    ///   - identityResponse: `ATI`の生応答。
    ///   - extendedProbeAccepted: 追加プローブを受け付けたかどうか。未実施ならnil。
    /// - Returns: 判定したチップ系統。
    func classify(stnIdentityResponse: String, identityResponse: String, extendedProbeAccepted: Bool?) -> OBDAdapterChipFamily {
        guard let stnLine = Self.firstMeaningfulLine(of: stnIdentityResponse) else { return .unknown }
        if stnLine.hasPrefix("STN") { return .stn }
        guard stnLine == "?", let version = Self.elm327Version(in: identityResponse) else { return .unknown }
        if version == Self.cloneVersion { return .elm327Clone }
        switch extendedProbeAccepted {
        case true?: return .elm327Genuine
        case false?: return .elm327Clone
        case nil: return .unknown
        }
    }

    /// 純正/クローン判別に追加プローブが必要かどうかを判定します。
    ///
    /// 責務: STNでなく`ELM327 v1.5`以外の空でないバージョンを名乗る応答だけを追加プローブ対象にします。
    /// - Parameters:
    ///   - stnIdentityResponse: `STI`の生応答。
    ///   - identityResponse: `ATI`の生応答。
    /// - Returns: 追加プローブが必要ならtrue。
    func requiresExtendedProbe(stnIdentityResponse: String, identityResponse: String) -> Bool {
        guard Self.firstMeaningfulLine(of: stnIdentityResponse) == "?",
              let version = Self.elm327Version(in: identityResponse) else { return false }
        return version != Self.cloneVersion
    }

    /// 生応答から評価対象の最初の行を取り出します。
    ///
    /// 責務: 行分割・プロンプト除去・trim・空行とエコー行の除去を行い、最初の行を大文字で返します。
    /// - Parameter response: アダプターの生応答。
    /// - Returns: 大文字化した最初の有効行。なければnil。
    private static func firstMeaningfulLine(of response: String) -> String? {
        response
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .lazy
            .map { $0.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces).uppercased() }
            .first { !$0.isEmpty && !echoCommands.contains($0) }
    }

    /// `ATI`応答からELM327のバージョン部を取り出します。
    ///
    /// 責務: 最初の有効行が`ELM327 v<空でないバージョン>`形式の時だけ大文字のバージョン部を返します。
    /// - Parameter identityResponse: `ATI`の生応答。
    /// - Returns: 大文字化したバージョン部。形式外ならnil。
    private static func elm327Version(in identityResponse: String) -> String? {
        guard let line = firstMeaningfulLine(of: identityResponse), line.hasPrefix(elm327VersionPrefix) else { return nil }
        let version = line.dropFirst(elm327VersionPrefix.count).trimmingCharacters(in: .whitespaces)
        return version.isEmpty ? nil : version
    }
}
