/// 分析の準備や読み込みで起きた失敗です。成功や空データには潰しません。
nonisolated enum AnalysisFailure: Error, Equatable, Sendable {
    /// 指定のセッションが存在しない。
    case sessionNotFound
    /// セッションの車両が存在しない。
    case vehicleNotFound
    /// Rawがこの端末に無い(iCloudにだけある)。
    case rawUnavailable
    /// Rawの要求が、セッションの取得条件に存在しない。
    case inconsistentRaw
    /// セッションにサンプルが1件も無い。
    case noSamples
    /// 永続化の読み出しに失敗した。
    case store
    /// iCloudからのRawのダウンロードに失敗した。
    case downloadFailed(CloudSyncFailure)
    /// 同時に比較できるセッション数の上限を超える。
    case tooManySessions
    /// 分析データの符号化に失敗した。
    case encoding

    /// Webワークベンチの文言表と対応する、安定した種別名です。
    var kind: String {
        switch self {
        case .sessionNotFound: "sessionNotFound"
        case .vehicleNotFound: "vehicleNotFound"
        case .rawUnavailable: "rawUnavailable"
        case .inconsistentRaw: "inconsistentRaw"
        case .noSamples: "noSamples"
        case .store: "store"
        case .downloadFailed: "downloadFailed"
        case .tooManySessions: "tooManySessions"
        case .encoding: "encoding"
        }
    }
}
