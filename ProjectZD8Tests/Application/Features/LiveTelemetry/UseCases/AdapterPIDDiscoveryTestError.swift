/// テストが意図して投げる、Domainに存在しないエラーです。
enum AdapterPIDDiscoveryTestError: Error, Equatable {
    /// アダプター通信の失敗を表します。
    case adapterFailed
    /// カタログ読込の失敗を表します。
    case catalogFailed
    /// fake への照会回数が上限を超えました(照会が止まらない不具合を停止ではなく失敗にするため)。
    case queryLimitExceeded
}
