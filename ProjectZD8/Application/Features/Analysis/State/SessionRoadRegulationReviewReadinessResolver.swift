import Foundation

/// 走行ルートの読み込みの段階と解析の読み込みの段階から、交通規制の照合を始められるかを決めます。
///
/// 解析の段階(`SessionLogAnalysisState.Phase`)が既定の MainActor の型なので、この型も既定の MainActor です。
struct SessionRoadRegulationReviewReadinessResolver {
    /// 状態を持たない判定器を作ります。
    ///
    /// 責務: 規則だけで照合の準備を決める判定器を用意します。
    init() {}

    /// 照合の準備の段階を決めます。
    ///
    /// 責務: ルートが ready でなければルートの段階で、ready なら解析の段階で準備を決めます。
    /// - Parameters:
    ///   - routePhase: 走行ルートの読み込みの段階。
    ///   - analysisPhase: 解析(Raw)の読み込みの段階。
    /// - Returns: 照合の準備の段階。
    func readiness(routePhase: RouteAnalysisLoadPhase, analysisPhase: SessionLogAnalysisState.Phase) -> SessionRoadRegulationReviewReadiness {
        switch routePhase {
        case .idle, .waitingForAccount, .loading: .waitingForRoute
        case .unavailable, .failed: .routeUnavailable
        case .ready: readinessAfterRoute(analysisPhase: analysisPhase)
        }
    }

    /// 表示中のセッションと、ルート・解析の状態がどのセッションのものかを照らして、照合の準備の段階を決めます。
    ///
    /// 責務: ルートの状態が別のセッションのものなら `waitingForRoute`、ルートは一致して ready だが解析の状態が
    /// 別のセッションのものなら `waitingForRawLog` にし、どちらも一致すれば段階だけで決めます。
    /// - Parameters:
    ///   - sessionID: 表示中のセッションの ID。
    ///   - routeSessionID: 走行ルートの状態が表すセッションの ID(未選択なら nil)。
    ///   - routePhase: 走行ルートの読み込みの段階。
    ///   - analysisSessionID: 解析の状態が表すセッションの ID(未選択なら nil)。
    ///   - analysisPhase: 解析(Raw)の読み込みの段階。
    /// - Returns: 照合の準備の段階。
    func readiness(
        for sessionID: ConnectionSessionID,
        routeSessionID: ConnectionSessionID?,
        routePhase: RouteAnalysisLoadPhase,
        analysisSessionID: ConnectionSessionID?,
        analysisPhase: SessionLogAnalysisState.Phase
    ) -> SessionRoadRegulationReviewReadiness {
        guard routeSessionID == sessionID else { return .waitingForRoute }
        let readiness = readiness(routePhase: routePhase, analysisPhase: analysisPhase)
        guard analysisSessionID != sessionID, case .ready = readiness else { return readiness }
        return .waitingForRawLog
    }

    /// ルートが ready の時の準備の段階を決めます。
    ///
    /// 責務: Raw の取得中・読み込み中は待ち、置き場所が決まったらその置き場所で ready にします。
    /// - Parameter analysisPhase: 解析(Raw)の読み込みの段階。
    /// - Returns: 照合の準備の段階。
    private func readinessAfterRoute(analysisPhase: SessionLogAnalysisState.Phase) -> SessionRoadRegulationReviewReadiness {
        switch analysisPhase {
        case .idle, .downloading, .loading: .waitingForRawLog
        case .awaitingDownloadConfirmation: .ready(.inCloud)
        case .loaded: .ready(.onDevice)
        case .failed: .ready(.unreadable)
        }
    }
}
