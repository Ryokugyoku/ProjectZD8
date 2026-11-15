/// 応答駆動の取得ループの診断記録を、統合ログへ出す固定文言へ整形します。
///
/// 実機テスト手順書がこの文字列を参照するため、文言を変える場合は手順書も合わせて直します。
struct LiveTelemetryAcquisitionDiagnosticsMessageFormatter {
    /// 文言の共通の接頭辞です。
    private static let prefix = "Acquisition"

    /// 取得を始めたときの文言です。
    ///
    /// 責務: 取得開始を固定文言へ変換します。
    /// - Returns: `Acquisition started`。
    func started() -> String {
        "\(Self.prefix) started"
    }

    /// 段階が変わったときの文言です。
    ///
    /// 責務: 段階・原因・回復段階・試行番号を固定文言へ変換します。
    /// - Parameter phase: 変化後の段階。
    /// - Returns: `Acquisition phase: acquiring`、
    ///   `Acquisition phase: recovering cause=<cause> stage=<stage> attempt=<n>`、または `Acquisition phase: paused cause=<cause>`。
    func phaseChanged(_ phase: LiveTelemetryAcquisitionPhase) -> String {
        switch phase {
        case .acquiring:
            "\(Self.prefix) phase: acquiring"
        case let .recovering(cause, stage, attempt):
            "\(Self.prefix) phase: recovering cause=\(Self.name(of: cause)) stage=\(Self.name(of: stage)) attempt=\(attempt)"
        case let .paused(cause):
            "\(Self.prefix) phase: paused cause=\(Self.name(of: cause))"
        }
    }

    /// 停止で終わったときの文言です。
    ///
    /// 責務: 停止による終了を固定文言へ変換します。
    /// - Returns: `Acquisition ended: stopped`。
    func stopped() -> String {
        "\(Self.prefix) ended: stopped"
    }

    /// 猶予切れで終わったときの文言です。
    ///
    /// 責務: 猶予切れによる終了とその原因を固定文言へ変換します。
    /// - Parameter cause: 取得が途切れた原因。
    /// - Returns: `Acquisition ended: gracePeriodExpired cause=<cause>`。
    func gracePeriodExpired(cause: LiveTelemetryInterruptionCause) -> String {
        "\(Self.prefix) ended: gracePeriodExpired cause=\(Self.name(of: cause))"
    }

    /// 記録失敗で終わったときの文言です。
    ///
    /// 責務: 記録失敗による終了を固定文言へ変換します。
    /// - Returns: `Acquisition ended: recordingFailed`。
    func recordingFailed() -> String {
        "\(Self.prefix) ended: recordingFailed"
    }

    /// 途切れの原因の文言上の名前です。
    ///
    /// 責務: 原因を `responseStall` または `linkLost` へ変換します。
    /// - Parameter cause: 名前にする原因。
    /// - Returns: 原因の名前。
    private static func name(of cause: LiveTelemetryInterruptionCause) -> String {
        switch cause {
        case .responseStall: "responseStall"
        case .linkLost: "linkLost"
        }
    }

    /// 回復段階の文言上の名前です。
    ///
    /// 責務: 回復段階を `promptResync`・`reinitializeFromReset`・`reconnectLink` へ変換します。
    /// - Parameter stage: 名前にする回復段階。
    /// - Returns: 回復段階の名前。
    private static func name(of stage: AcquisitionRecoveryStage) -> String {
        switch stage {
        case .promptResync: "promptResync"
        case .reinitializeFromReset: "reinitializeFromReset"
        case .reconnectLink: "reconnectLink"
        }
    }
}
