/// 軌跡を表示に使えるかの結果です。
nonisolated enum ConnectionSessionLocationTrackAvailability: Equatable, Sendable {
    /// 軌跡を使える。
    case available(ConnectionSessionLocationTrack, ConnectionSessionLocationTrackSource)
    /// ローカルに無く、iCloud にもレコードが無い(未送信・記録なし・旧版)。空データとは区別する。
    case notInCloud
}
