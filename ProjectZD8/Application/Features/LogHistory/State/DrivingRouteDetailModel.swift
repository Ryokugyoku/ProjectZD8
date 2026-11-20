import Foundation
import Observation

/// セッション詳細の走行ルート(地図)の読み込みと状態を持ちます。
///
/// 型付きの Action を、軌跡の読み込み(`LoadConnectionSessionLocationTrackUseCase` を包んだ closure)と状態の更新へ変換します。
/// - 判定・形・文言の選択は純粋型(Resolver・ContentBuilder・Formatter・Classifier)に任せ、ここは流れだけを持ちます。
/// - 区切りと形の計算はメインの外(`Task.detached`)で行い、要約の文言はメインで整形します。
/// - 世代の番号で、別のセッションへ切り替えた後に届いた古い結果を捨てます。取消(`CancellationError`)は状態を変えません。
/// - 隔離はプロジェクト既定の MainActor です。`@MainActor` を明示すると、既定の MainActor の `DrivingRouteSummaryFormatter()` を
///   既定引数で作る所に隔離の警告が出るため、明示していません。
@Observable
final class DrivingRouteDetailModel {
    /// メインの外で計算した、表示の状態・地図の形・要約です。
    private typealias Computation = (status: DrivingRouteStatus, geometry: DrivingRouteMapGeometry?, summary: DrivingRouteSummary?)

    /// 画面へ公開する状態です。
    private(set) var state = DrivingRouteDetailState(sessionID: nil, phase: .idle)

    /// 軌跡を読み込む処理です(セッション ID とアカウント識別子を受け取ります)。
    @ObservationIgnored private let load: @MainActor (ConnectionSessionID, String) async throws -> ConnectionSessionLocationTrackAvailability
    /// 取得結果から表示の状態を決める部品です。
    @ObservationIgnored private let resolver: DrivingRouteStatusResolver
    /// 地図に描く形を作る部品です。
    @ObservationIgnored private let geometryBuilder: DrivingRouteMapContentBuilder
    /// 要約を計算する部品です。
    @ObservationIgnored private let summaryCalculator: DrivingRouteSummaryCalculator
    /// 要約を文字列へ整形する部品です。
    @ObservationIgnored private let summaryFormatter: DrivingRouteSummaryFormatter
    /// 読み込みの失敗を分類する部品です。
    @ObservationIgnored private let failureClassifier: DrivingRouteFailureClassifier
    /// サインイン中のアカウント識別子です。サインインしていなければ `nil` です。
    @ObservationIgnored private var accountIdentifier: String?
    /// 表示中のセッションです。表示していなければ `nil` です。
    @ObservationIgnored private var session: ConnectionSession?
    /// 実行中の読み込みです。
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// 読み込みの世代の番号です。取り消しと開始のたびに進め、古い結果を捨てるのに使います。
    @ObservationIgnored private var generation = 0

    /// 読み込みの処理と純粋な部品を固定して生成します。
    ///
    /// 責務: 読み込みの closure と、状態・形・要約・失敗の部品を保持し、`idle` から始めます。
    /// - Parameters:
    ///   - load: 軌跡を読み込む処理。
    ///   - resolver: 取得結果から表示の状態を決める部品。
    ///   - geometryBuilder: 地図に描く形を作る部品。
    ///   - summaryCalculator: 要約を計算する部品。
    ///   - summaryFormatter: 要約を文字列へ整形する部品。
    ///   - failureClassifier: 読み込みの失敗を分類する部品。
    init(
        load: @escaping @MainActor (ConnectionSessionID, String) async throws -> ConnectionSessionLocationTrackAvailability,
        resolver: DrivingRouteStatusResolver = .init(),
        geometryBuilder: DrivingRouteMapContentBuilder = .init(),
        summaryCalculator: DrivingRouteSummaryCalculator = .init(),
        summaryFormatter: DrivingRouteSummaryFormatter = .init(),
        failureClassifier: DrivingRouteFailureClassifier = .init()
    ) {
        self.load = load
        self.resolver = resolver
        self.geometryBuilder = geometryBuilder
        self.summaryCalculator = summaryCalculator
        self.summaryFormatter = summaryFormatter
        self.failureClassifier = failureClassifier
    }

    /// 実行中の読み込みを取り消します。
    deinit {
        loadTask?.cancel()
    }

    /// 画面からの操作を受け取ります。
    ///
    /// 責務: Action の種類ごとに、アカウントの更新・表示・非表示・再試行の処理へ振り分けます。
    /// - Parameter action: 画面からの操作。
    func send(_ action: DrivingRouteDetailAction) {
        switch action {
        case .accountIdentifierChanged(let identifier):
            changeAccount(to: identifier)
        case .sessionShown(let session):
            show(session)
        case .sessionHidden(let sessionID):
            hide(sessionID)
        case .retryRequested:
            retry()
        }
    }

    /// 実行中の読み込み(置き換わった読み込みを含む)が終わるまで待ちます。テスト用です。
    ///
    /// 責務: 実行中の Task の終了を順に待ち、同じ Task が残っていれば待つのをやめます。
    func waitUntilIdle() async {
        while let task = loadTask {
            await task.value
            if loadTask == task {
                return
            }
        }
    }

    /// アカウントの変更を反映します。
    ///
    /// 責務: 値が変わった時だけ読み込みを取り消して内容を捨て、表示中のセッションがあれば読み直します。
    /// - Parameter identifier: 新しいアカウント識別子(空文字はサインインなしとみなします)。
    private func changeAccount(to identifier: String?) {
        let normalized = identifier?.isEmpty == true ? nil : identifier
        guard normalized != accountIdentifier else {
            return
        }
        accountIdentifier = normalized
        cancelLoad()
        guard session != nil else {
            state = DrivingRouteDetailState(sessionID: nil, phase: .idle)
            return
        }
        begin()
    }

    /// セッションの表示を反映します。
    ///
    /// 責務: 終了済みで読み込み済みの同じセッションなら何もせず、それ以外は前の読み込みを取り消して読み始めます。
    /// - Parameter session: 表示されたセッション。
    private func show(_ session: ConnectionSession) {
        if case .loaded = state.phase, state.sessionID == session.id, session.endedAt != nil {
            return
        }
        cancelLoad()
        self.session = session
        state.sessionID = session.id
        begin()
    }

    /// セッションの非表示を反映します。
    ///
    /// 責務: 表示中のセッションと一致する時だけ、読み込みを取り消して `idle` に戻します。
    /// - Parameter sessionID: 閉じられたセッションの ID。
    private func hide(_ sessionID: ConnectionSessionID) {
        guard session?.id == sessionID else {
            return
        }
        cancelLoad()
        session = nil
        state = DrivingRouteDetailState(sessionID: nil, phase: .idle)
    }

    /// 再試行の要求を反映します。
    ///
    /// 責務: 再試行できる失敗の時だけ読み直します。
    private func retry() {
        guard case .failed(let failure) = state.phase, failure.isRetryable, session != nil else {
            return
        }
        cancelLoad()
        begin()
    }

    /// 表示中のセッションの読み込みを始めます。
    ///
    /// 責務: アカウントが無ければ待ちの状態にし、あれば `loading` にして新しい世代の読み込みを起動します。
    private func begin() {
        guard let session else {
            return
        }
        guard let accountIdentifier else {
            state.phase = .waitingForAccount
            return
        }
        state.phase = .loading
        generation += 1
        let current = generation
        loadTask = Task { [weak self] in
            await self?.perform(session: session, accountIdentifier: accountIdentifier, generation: current)
        }
    }

    /// 実行中の読み込みを取り消し、世代を進めます。
    ///
    /// 責務: Task を取り消して手放し、遅れて届く結果を古い世代として捨てさせます。
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        generation += 1
    }

    /// 1回の読み込みを行い、結果を状態へ反映します。
    ///
    /// 責務: 読み込み・メイン外の計算・整形を順に行い、世代が変わっていなければ結果か失敗を反映します。
    /// - Parameters:
    ///   - session: 対象のセッション。
    ///   - accountIdentifier: 対象のアカウント。
    ///   - generation: この読み込みの世代。
    private func perform(session: ConnectionSession, accountIdentifier: String, generation: Int) async {
        defer { releaseTask(ifCurrent: generation) }
        do {
            let availability = try await load(session.id, accountIdentifier)
            guard self.generation == generation,
                  let computation = await compute(availability, session: session),
                  self.generation == generation
            else {
                return
            }
            state.phase = phase(for: computation)
        } catch is CancellationError {
            return
        } catch {
            guard self.generation == generation else {
                return
            }
            state.phase = .failed(failureClassifier.failure(for: error))
        }
    }

    /// 終わった読み込みの Task を手放します。
    ///
    /// 責務: 世代が変わっていない時だけ、実行中の Task を空にします(新しい世代の Task は残します)。
    /// - Parameter generation: 終わった読み込みの世代。
    private func releaseTask(ifCurrent generation: Int) {
        guard self.generation == generation else {
            return
        }
        loadTask = nil
    }

    /// 区切り・形・要約の計算をメインの外で行います。
    ///
    /// 責務: 純粋な部品を `Task.detached` へ渡して計算させ、呼び出し側の取消を伝えます。
    /// - Parameters:
    ///   - availability: 軌跡の取得結果。
    ///   - session: 対象のセッション。
    /// - Returns: 計算の結果。取り消された時は `nil`。
    private func compute(
        _ availability: ConnectionSessionLocationTrackAvailability,
        session: ConnectionSession
    ) async -> Computation? {
        let resolver = resolver
        let geometryBuilder = geometryBuilder
        let summaryCalculator = summaryCalculator
        let task = Task.detached(priority: .userInitiated) { () -> Computation? in
            guard !Task.isCancelled else {
                return nil
            }
            let computation = Self.computation(
                availability,
                session: session,
                resolver: resolver,
                geometryBuilder: geometryBuilder,
                summaryCalculator: summaryCalculator
            )
            return Task.isCancelled ? nil : computation
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 取得結果から、表示の状態・地図の形・要約を計算します。
    ///
    /// 責務: 状態を決め、描くルートがある時だけ形と要約を作ります。
    /// - Parameters:
    ///   - availability: 軌跡の取得結果。
    ///   - session: 対象のセッション(開始・終了の時刻)。
    ///   - resolver: 表示の状態を決める部品。
    ///   - geometryBuilder: 地図に描く形を作る部品。
    ///   - summaryCalculator: 要約を計算する部品。
    /// - Returns: 計算の結果。
    nonisolated private static func computation(
        _ availability: ConnectionSessionLocationTrackAvailability,
        session: ConnectionSession,
        resolver: DrivingRouteStatusResolver,
        geometryBuilder: DrivingRouteMapContentBuilder,
        summaryCalculator: DrivingRouteSummaryCalculator
    ) -> Computation {
        let status = resolver.status(for: availability)
        guard let route = status.route else {
            return (status, nil, nil)
        }
        let geometry = geometryBuilder.geometry(for: route, sessionHasEnded: session.endedAt != nil)
        let summary = summaryCalculator.summary(of: route, sessionStartedAt: session.startedAt, sessionEndedAt: session.endedAt)
        return (status, geometry, summary)
    }

    /// 計算の結果を、画面の段階へ変換します。
    ///
    /// 責務: 形と要約があれば地図の内容に、無ければ理由と注記にします(空の地図は出しません)。
    /// - Parameter computation: 計算の結果。
    /// - Returns: 画面の段階。
    private func phase(for computation: Computation) -> DrivingRouteDetailPhase {
        let noticeKeys = computation.status.noticeKeys
        if let geometry = computation.geometry, let summary = computation.summary {
            let content = DrivingRouteMapContent(geometry: geometry, summary: summaryFormatter.text(for: summary), noticeKeys: noticeKeys)
            return .loaded(content)
        }
        let absence = computation.status.absence ?? DrivingRouteTextKeys().absence(.notRecorded)
        return .unavailable(absence, noticeKeys: noticeKeys)
    }
}
