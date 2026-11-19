/// リアルタイム表示の現在段階を、バナーの文言キー・記号・調子・進捗表示へ変換した表示内容です。
///
/// iOSとmacOSで共通の判定です。表示すべき状態がない段階では生成しません。
struct LiveTelemetryStatusBanner: Equatable {
    /// 状態を表すローカライズキーです。
    let key: String
    /// 状態を補助するSF Symbol名です。
    let symbol: String
    /// バナーの調子です。
    let tone: LiveTelemetryStatusBannerTone
    /// 未完了の処理を示す進捗表示を出すかどうかです。
    let showsProgress: Bool

    /// 失敗の理由が分からない時に使うローカライズキーです。
    static let readFailedKey = "telemetry.error.read_failed"
    /// 失敗・接続断の後に使うSF Symbol名です。
    static let failureSymbol = "exclamationmark.triangle.fill"

    /// 表示内容を各値から生成します。
    ///
    /// 責務: バナーの4項目を1件の表示内容へまとめます。
    /// - Parameters:
    ///   - key: 状態を表すローカライズキー。
    ///   - symbol: 状態を補助するSF Symbol名。
    ///   - tone: バナーの調子。
    ///   - showsProgress: 進捗表示を出す場合は `true`。
    init(key: String, symbol: String, tone: LiveTelemetryStatusBannerTone, showsProgress: Bool) {
        self.key = key
        self.symbol = symbol
        self.tone = tone
        self.showsProgress = showsProgress
    }

    /// リアルタイム表示の状態からバナーを生成します。
    ///
    /// 責務: 取得段階と失敗・一時停止の情報を1件のバナーへ変換し、表示する状態がなければ生成しません。
    /// - Parameter state: 現在のリアルタイム表示状態。
    /// - Returns: 表示するバナー。一時停止で `pauseStatus` がない場合と、失敗理由のない待機中は `nil`。
    init?(state: LiveTelemetryState) {
        guard let banner = Self.banner(for: state) else { return nil }
        self = banner
    }

    /// 段階ごとの規則でバナーを選びます。
    ///
    /// 責務: 1件の取得段階を対応するバナーへ振り分けます。
    /// - Parameter state: 現在のリアルタイム表示状態。
    /// - Returns: 段階に対応するバナー。表示しない場合は `nil`。
    private static func banner(for state: LiveTelemetryState) -> LiveTelemetryStatusBanner? {
        switch state.phase {
        case .reading:
            LiveTelemetryStatusBanner(key: "telemetry.status.reading", symbol: "dot.radiowaves.left.and.right", tone: .active, showsProgress: true)
        case .loaded:
            LiveTelemetryStatusBanner(key: "telemetry.status.polling", symbol: "waveform.path.ecg", tone: .healthy, showsProgress: false)
        case .paused:
            pausedBanner(state.pauseStatus)
        case .stopping:
            LiveTelemetryStatusBanner(key: "telemetry.status.stopping", symbol: "stop.circle", tone: .warning, showsProgress: true)
        case .failed:
            failureBanner(key: state.failureKey ?? readFailedKey)
        case .idle:
            state.failureKey.map { failureBanner(key: $0) }
        }
    }

    /// 一時停止中のバナーを生成します。
    ///
    /// 責務: 回復中・猶予待ちの表示状態を警告バナーへ変換します。
    /// - Parameter pauseStatus: 一時停止中の表示状態。
    /// - Returns: 一時停止のバナー。表示状態がなければ `nil`。
    private static func pausedBanner(_ pauseStatus: LiveTelemetryPauseStatus?) -> LiveTelemetryStatusBanner? {
        guard let pauseStatus else { return nil }
        return LiveTelemetryStatusBanner(
            key: pauseStatus.statusKey,
            symbol: "pause.circle",
            tone: .warning,
            showsProgress: pauseStatus.isRecovering
        )
    }

    /// 失敗・接続断のバナーを生成します。
    ///
    /// 責務: 失敗理由の文言キーを進捗なしの警告バナーへ変換します。
    /// - Parameter key: 失敗理由のローカライズキー。
    /// - Returns: 失敗のバナー。
    private static func failureBanner(key: String) -> LiveTelemetryStatusBanner {
        LiveTelemetryStatusBanner(key: key, symbol: failureSymbol, tone: .warning, showsProgress: false)
    }
}
