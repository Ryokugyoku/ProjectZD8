import Foundation

/// 時間窓の間に常駐リンクから集めた受信バイトと、プロンプトで窓が終わったかどうかです。
nonisolated struct AdapterLinkCollectedBytes: Equatable, Sendable {
    /// 集めた受信バイトです。プロンプトで終わった場合は `>` を含みます。
    let data: Data
    /// 時間窓の終了前にプロンプト `>` が届いて終わった場合は `true` です。
    let endedWithPrompt: Bool
}
