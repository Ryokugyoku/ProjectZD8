import Observation

/// 主要PID読取操作をApplicationユースケースへ結び付けます。
@MainActor
@Observable
final class LiveTelemetryModel {
    /// Platformが描画する現在状態です。
    var state: LiveTelemetryState
    /// 検証済み主要PIDを数値化するユースケースです。
    @ObservationIgnored private let readMajorPIDs: ReadMajorOBDPIDsUseCase

    /// 初期状態と主要PID読取ユースケースを固定します。
    ///
    /// 責務: PID表示状態を1件の読取ユースケースへ結び付けます。
    /// - Parameters:
    ///   - state: Platformへ公開する初期状態。
    ///   - readMajorPIDs: 主要PID読取と数値化を行うユースケース。
    init(state: LiveTelemetryState = .init(), readMajorPIDs: ReadMajorOBDPIDsUseCase) {
        self.state = state
        self.readMajorPIDs = readMajorPIDs
    }

    /// 型付き操作をPID読取ワークフローへ変換します。
    ///
    /// 責務: 1件のLiveTelemetry操作を新規読取または再読取に振り分けます。
    /// - Parameter action: Platformから通知された型付き操作。
    func send(_ action: LiveTelemetryAction) {
        switch action {
        case let .readRequested(endpoint):
            Task { await read(using: endpoint) }
        case .retryRequested:
            if let endpoint = state.endpoint { Task { await read(using: endpoint) } }
        }
    }

    /// 指定OBD終端から主要PIDを1回読み取ります。
    ///
    /// 責務: 1回の主要PID読取結果を成功または失敗状態へ反映します。
    /// - Parameter endpoint: OBDアダプターの物理終端。
    private func read(using endpoint: OBDConnectionEndpoint) async {
        guard state.phase != .reading else { return }
        state.endpoint = endpoint
        state.phase = .reading
        state.failureKey = nil
        do {
            state.samples = try await readMajorPIDs.execute(using: endpoint)
            state.phase = .loaded
        } catch OBDPIDTelemetryError.unavailable {
            state.phase = .failed
            state.failureKey = "telemetry.error.unavailable"
        } catch {
            state.phase = .failed
            state.failureKey = "telemetry.error.read_failed"
        }
    }
}
