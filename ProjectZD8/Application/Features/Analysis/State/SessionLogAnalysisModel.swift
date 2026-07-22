import Foundation
import Observation

/// セッションRawログ解析の状態遷移を保持します。
@MainActor @Observable
final class SessionLogAnalysisModel {
    /// 画面へ公開する解析状態です。
    private(set) var state: SessionLogAnalysisState
    /// 保存済みログを時系列表示へ変換するユースケースです。
    private let decodeTimeline: DecodeSessionLogTimelineUseCase
    /// 現在実行中の逐次解析処理です。
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// 初期状態と時系列変換ユースケースを注入して生成します。
    ///
    /// 責務: セッション解析状態と読取専用変換ワークフローを固定します。
    /// - Parameters:
    ///   - state: 初期表示状態。
    ///   - decodeTimeline: 保存済みRawログを変換するユースケース。
    init(state: SessionLogAnalysisState, decodeTimeline: DecodeSessionLogTimelineUseCase) {
        self.state = state
        self.decodeTimeline = decodeTimeline
    }

    /// 画面操作を解析状態遷移へ適用します。
    ///
    /// 責務: 1件の解析操作を対応する読込または表示終了状態へ変換します。
    /// - Parameter action: 適用する型付き解析操作。
    func send(_ action: SessionLogAnalysisAction) {
        switch action {
        case let .sessionSelected(sessionID): beginLoading(sessionID: sessionID)
        case .dismissed: dismiss()
        }
    }

    /// 指定セッションの逐次解析を開始します。
    ///
    /// 責務: 1件のセッションIDを画面遷移後に開始するキャンセル可能な解析処理へ変換します。
    /// - Parameter sessionID: 解析する保存済みセッションID。
    private func beginLoading(sessionID: ConnectionSessionID) {
        guard state.sessionID != sessionID || state.phase == .failed else { return }
        loadTask?.cancel()
        state = .init(phase: .loading, sessionID: sessionID)
        loadTask = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            do {
                try await decodeTimeline.execute(
                    sessionID: sessionID,
                    prepared: { [weak self] count in
                        guard self?.state.sessionID == sessionID else { return }
                        self?.state.totalSampleCount = count
                    },
                    batchDecoded: { [weak self] batch in
                        guard self?.state.sessionID == sessionID else { return }
                        self?.state.timeline.append(contentsOf: batch)
                        self?.state.decodedSampleCount += batch.lazy.filter { $0.value != nil }.count
                    }
                )
                guard state.sessionID == sessionID else { return }
                let timeline = state.timeline
                let visualizationTask = Task.detached(priority: .userInitiated) {
                    guard !Task.isCancelled else { return Optional<SessionLogVisualizationSnapshot>.none }
                    let snapshot = SessionLogVisualizationBuilder.build(from: timeline)
                    return Task.isCancelled ? nil : snapshot
                }
                let visualization = await withTaskCancellationHandler {
                    await visualizationTask.value
                } onCancel: {
                    visualizationTask.cancel()
                }
                guard let visualization, state.sessionID == sessionID else { return }
                state.pidSeries = visualization.series
                state.performanceSummary = visualization.performanceSummary
                state.componentInsights = visualization.componentInsights
                state.relationships = visualization.relationships
                state.phase = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard state.sessionID == sessionID else { return }
                state.phase = .failed
                state.failureKey = "analysis.timeline.error.storage"
            }
        }
    }

    /// 現在の解析を中止して表示状態を初期化します。
    ///
    /// 責務: 表示終了操作を解析キャンセルと空の解析状態へ変換します。
    private func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        state = .init()
    }
}
