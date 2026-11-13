#if os(iOS)
import Foundation

/// iOSがアプリへ許可するExternalAccessoryプロトコル文字列の構成です。
nonisolated struct IOSExternalAccessoryProtocolConfiguration: Equatable, Sendable {
    /// Apple標準のInfo.plistキーです。
    static let infoPlistKey = "UISupportedExternalAccessoryProtocols"

    /// 空白と重複を除いた利用可能プロトコル文字列です。
    let protocolStrings: Set<String>

    /// Info.plistの標準キーからプロトコル文字列を読み取ります。
    ///
    /// 責務: 1件のBundle設定をExternalAccessory通信の許可リストへ変換します。
    /// - Parameter bundle: 標準Info.plist値を提供するBundle。
    init(bundle: Bundle = .main) {
        self.init(
            protocolStrings: bundle.object(
                forInfoDictionaryKey: Self.infoPlistKey
            ) as? [String] ?? []
        )
    }

    /// 指定されたプロトコル文字列を正規化して保持します。
    ///
    /// 責務: メーカー確認済みプロトコル文字列だけを比較可能な許可集合へ固定します。
    /// - Parameter protocolStrings: Info.plistへ設定するExternalAccessoryプロトコル文字列。
    init(protocolStrings: [String]) {
        self.protocolStrings = Set(
            protocolStrings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    /// アプリとアクセサリーの双方が公開する最初のプロトコルを返します。
    ///
    /// 責務: 1件のアクセサリー公開値をメーカー確認済み許可集合と照合します。
    /// - Parameter accessoryProtocolStrings: ExternalAccessoryが公開したプロトコル文字列。
    /// - Returns: アプリの許可リスト順で最初に一致した文字列。一致しない場合は `nil`。
    func matchingProtocol(in accessoryProtocolStrings: [String]) -> String? {
        protocolStrings.sorted().first(where: accessoryProtocolStrings.contains)
    }
}
#endif
