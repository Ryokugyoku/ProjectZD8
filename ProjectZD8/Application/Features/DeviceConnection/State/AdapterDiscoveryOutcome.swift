/// 最新のアダプター探索がApplication境界へ返す結果です。
enum AdapterDiscoveryOutcome: Equatable {
    /// 候補一覧の取得に成功しました。
    case discovered([DiscoveredAdapter])

    /// 製品またはシステム状態により探索を利用できませんでした。
    case unavailable(AdapterDiscoveryError)

    /// 分類できないエラーにより探索を完了できませんでした。
    case failed
}
