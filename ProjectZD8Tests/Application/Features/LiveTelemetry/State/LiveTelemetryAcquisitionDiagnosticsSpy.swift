@testable import ProjectZD8

/// 取得ループの診断ポートへ伝えられた出来事を順に記録する spy です。
@MainActor
final class LiveTelemetryAcquisitionDiagnosticsSpy: LiveTelemetryAcquisitionDiagnosticsPort {
    /// 診断ポートへ伝えられた1件の出来事です。
    enum Event: Equatable {
        /// 取得を始めた。
        case started
        /// 段階が変わった。
        case phaseChanged(LiveTelemetryAcquisitionPhase)
        /// 停止で終わった。
        case stopped
        /// 猶予切れで終わった。
        case gracePeriodExpired(LiveTelemetryInterruptionCause)
        /// 記録失敗で終わった。
        case recordingFailed

        /// 終了の出来事かどうかです。
        var isTermination: Bool {
            switch self {
            case .stopped, .gracePeriodExpired, .recordingFailed: true
            case .started, .phaseChanged: false
            }
        }
    }

    /// 伝えられた出来事です。
    private(set) var events: [Event] = []

    /// 伝えられた段階の変化だけを、伝えられた順に返します。
    var phases: [LiveTelemetryAcquisitionPhase] {
        events.compactMap { event in
            if case let .phaseChanged(phase) = event { phase } else { nil }
        }
    }

    /// 伝えられた終了の出来事だけを返します。
    var terminations: [Event] {
        events.filter(\.isTermination)
    }

    /// 伝えられた取得開始の回数です。
    var startCount: Int {
        events.filter { $0 == .started }.count
    }

    /// 責務: 取得開始を記録します。
    func acquisitionStarted() {
        events.append(.started)
    }

    /// 責務: 段階の変化を記録します。
    /// - Parameter phase: 変化後の段階。
    func acquisitionPhaseChanged(_ phase: LiveTelemetryAcquisitionPhase) {
        events.append(.phaseChanged(phase))
    }

    /// 責務: 停止による終了を記録します。
    func acquisitionStopped() {
        events.append(.stopped)
    }

    /// 責務: 猶予切れによる終了と原因を記録します。
    /// - Parameter cause: 取得が途切れた原因。
    func acquisitionGracePeriodExpired(cause: LiveTelemetryInterruptionCause) {
        events.append(.gracePeriodExpired(cause))
    }

    /// 責務: 記録失敗による終了を記録します。
    func acquisitionRecordingFailed() {
        events.append(.recordingFailed)
    }
}
