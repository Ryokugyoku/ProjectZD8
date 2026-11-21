import Foundation
import Observation

/// 1回の走行の交通規制の照合(解析画面の「ルート」モードのカード)の読み込みと状態を持ちます。
///
/// 型付きの Action を、照合のポート(`SessionRoadRegulationReviewPort`)の呼び出しと状態の更新へ変換します。
/// - 画面ルートが送る準備の段階(`readinessChanged`)が `ready` になった時だけ照合を始め、それ以外の段階では結果と重ね合わせを捨てます。
/// - 結果から表示の内容を作る処理はメインの外(`Task.detached`)で行い、世代の番号で古い結果を捨てます
///   (別のセッション・別の Raw の状態へ切り替えた後の結果で上書きしません)。
/// - 重ね合わせ(`state.overlays`)は結果を出している時だけ空でなく、画面ルートが段階4へ送ります。
/// - 隔離はプロジェクト既定の MainActor です。
@Observable
final class SessionRoadRegulationReviewModel {
    /// 画面へ公開する状態です。
    private(set) var state = SessionRoadRegulationReviewState()

    /// 照合の結果を返すポートです。
    @ObservationIgnored private let reviewPort: any SessionRoadRegulationReviewPort
    /// 結果から表示の内容を作る部品です。
    @ObservationIgnored private let contentBuilder: SessionRoadRegulationReviewContentBuilder
    /// 種類ごとの一覧を作る部品です。
    @ObservationIgnored private let sectionBuilder: SessionRoadRegulationReviewSectionBuilder
    /// 段階4へ送る重ね合わせを作る部品です。
    @ObservationIgnored private let overlayBuilder: SessionRoadRegulationReviewOverlayBuilder
    /// サインイン中のアカウント識別子です。サインインしていなければ `nil` です。
    @ObservationIgnored private var accountIdentifier: String?
    /// 最後に受け取った準備の段階です。
    @ObservationIgnored private var lastReadiness: SessionRoadRegulationReviewReadiness?
    /// 実行中、または結果を出した照合の入力(Raw の状態)です。
    @ObservationIgnored private var evaluatedRawLog: SessionRoadRegulationRawLogAvailability?
    /// 結果から作った行(絞り込み前)です。
    @ObservationIgnored private var rows: [SessionRoadRegulationReviewRow] = []
    /// 実行中の照合です。
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 照合の世代の番号です。
    @ObservationIgnored private var generation = 0

    /// ポートと純粋な部品を固定して生成します。
    ///
    /// 責務: 照合のポートと、内容・一覧・重ね合わせを作る部品を保持し、`idle` から始めます。
    /// - Parameters:
    ///   - reviewPort: 照合の結果を返すポート。
    ///   - contentBuilder: 結果から表示の内容を作る部品。
    ///   - sectionBuilder: 種類ごとの一覧を作る部品。
    ///   - overlayBuilder: 重ね合わせを作る部品。
    init(
        reviewPort: any SessionRoadRegulationReviewPort,
        contentBuilder: SessionRoadRegulationReviewContentBuilder = .init(),
        sectionBuilder: SessionRoadRegulationReviewSectionBuilder = .init(),
        overlayBuilder: SessionRoadRegulationReviewOverlayBuilder = .init()
    ) {
        self.reviewPort = reviewPort
        self.contentBuilder = contentBuilder
        self.sectionBuilder = sectionBuilder
        self.overlayBuilder = overlayBuilder
    }

    /// 実行中の照合を取り消します。
    deinit {
        task?.cancel()
    }

    /// 画面からの操作を受け取ります。
    ///
    /// 責務: Action の種類ごとに、アカウント・準備の段階・絞り込み・行の選択・再試行・閉じる処理へ振り分けます。
    /// - Parameter action: 画面からの操作。
    func send(_ action: SessionRoadRegulationReviewAction) {
        switch action {
        case .accountIdentifierChanged(let identifier):
            changeAccount(to: identifier)
        case .readinessChanged(let sessionID, let readiness):
            receiveReadiness(readiness, for: sessionID)
        case .filterChanged(let filter):
            changeFilter(to: filter)
        case .rowSelected(let rowID):
            selectRow(rowID)
        case .retryRequested:
            retry()
        case .dismissed:
            dismiss()
        }
    }

    /// 実行中の照合(置き換わったものを含む)が終わるまで待ちます。テスト用です。
    ///
    /// 責務: 実行中の Task の終了を順に待ち、同じ Task が残っていれば待つのをやめます。
    func waitUntilIdle() async {
        while let task {
            await task.value
            if self.task == task {
                return
            }
        }
    }

    /// アカウントの変更を反映します。
    ///
    /// 責務: 値が変わった時だけ照合を取り消し、内部の状態と表示をすべて捨てます(準備の段階は画面ルートが送り直します)。
    /// - Parameter identifier: 新しいアカウント識別子(空文字はサインインなしとみなします)。
    private func changeAccount(to identifier: String?) {
        let normalized = identifier?.isEmpty == true ? nil : identifier
        guard normalized != accountIdentifier else {
            return
        }
        accountIdentifier = normalized
        resetAll()
    }

    /// 準備の段階を反映します。
    ///
    /// 責務: 別のセッションなら内容と絞り込み・選択を捨ててから、待ちの段階なら結果を捨てて同名の段階にし、
    /// `ready` なら同じ入力の重複を除いて照合を始めます。最後に受け取った段階を覚えます。
    /// - Parameters:
    ///   - readiness: 準備の段階。
    ///   - sessionID: 表示中のセッション ID。
    private func receiveReadiness(_ readiness: SessionRoadRegulationReviewReadiness, for sessionID: ConnectionSessionID) {
        if state.sessionID != sessionID {
            cancelEvaluation()
            evaluatedRawLog = nil
            state = SessionRoadRegulationReviewState(sessionID: sessionID)
        }
        lastReadiness = readiness
        guard case .ready(let rawLog) = readiness else {
            cancelEvaluation()
            evaluatedRawLog = nil
            clearContent(status: Self.waitingStatus(for: readiness))
            return
        }
        guard !isDuplicateEvaluation(of: rawLog) else {
            return
        }
        beginEvaluation(sessionID: sessionID, rawLog: rawLog)
    }

    /// 同じ入力の照合を実行中、または結果を出している時に `true` を返します。
    ///
    /// 責務: 前回の入力の Raw の状態が同じで、状態が照合中か結果(失敗を含む)を出している段階かを判定します。
    /// - Parameter rawLog: 新しく受け取った Raw の状態。
    /// - Returns: 照合を始め直さなくてよい時に `true`。
    private func isDuplicateEvaluation(of rawLog: SessionRoadRegulationRawLogAvailability) -> Bool {
        guard evaluatedRawLog == rawLog else {
            return false
        }
        let settledStatuses: [SessionRoadRegulationReviewStatus] = [.evaluating, .loaded, .noTrack, .noRegulationData, .failed]
        return settledStatuses.contains(state.status)
    }

    /// 絞り込みの変更を反映します。
    ///
    /// 責務: 同じなら何もせず、違えば絞り込みを変え、結果を出している時は一覧を作り直します。選択中の行が見えなくなったら選択を外して重ね合わせを作り直します。
    /// - Parameter filter: 新しい絞り込み。
    private func changeFilter(to filter: SessionRoadRegulationReviewFilter) {
        guard state.filter != filter else {
            return
        }
        state.filter = filter
        guard state.status == .loaded else {
            return
        }
        state.sections = sectionBuilder.sections(for: rows, filter: filter)
        if let selectedRowID = state.selectedRowID, !sectionBuilder.isVisible(rowID: selectedRowID, in: state.sections) {
            state.selectedRowID = nil
            rebuildOverlays()
        }
    }

    /// 行の選択を反映します。
    ///
    /// 責務: 結果を出していて、その行が一覧に見えている時だけ、同じ行なら選択を外し、違えば選び、重ね合わせを作り直します。
    /// - Parameter rowID: 選ばれた行の id。
    private func selectRow(_ rowID: Int) {
        guard state.status == .loaded, sectionBuilder.isVisible(rowID: rowID, in: state.sections) else {
            return
        }
        state.selectedRowID = state.selectedRowID == rowID ? nil : rowID
        rebuildOverlays()
    }

    /// 再試行の要求を反映します。
    ///
    /// 責務: 失敗している時で、最後に受け取った段階が `ready` の時だけ、同じ入力で照合をやり直します。
    private func retry() {
        guard state.status == .failed, case .ready(let rawLog)? = lastReadiness, let sessionID = state.sessionID else {
            return
        }
        beginEvaluation(sessionID: sessionID, rawLog: rawLog)
    }

    /// カードを閉じます。
    ///
    /// 責務: 照合を取り消し、内部の状態と表示をすべて捨てて初期の状態に戻します(アカウントは保持します)。
    private func dismiss() {
        resetAll()
    }

    /// 照合を取り消し、アカウント以外の内部の状態と表示をすべて捨てます。
    ///
    /// 責務: 実行中の照合を取り消し、最後の段階・照合の入力・行を捨て、状態を初期値(重ね合わせも空)にします。
    private func resetAll() {
        cancelEvaluation()
        lastReadiness = nil
        evaluatedRawLog = nil
        state = SessionRoadRegulationReviewState()
    }

    /// 実行中の照合を取り消し、作った行を捨てます。
    ///
    /// 責務: Task を取り消して手放し、世代を進めて、遅れて届く結果を古い世代として捨てさせます。
    private func cancelEvaluation() {
        task?.cancel()
        task = nil
        generation += 1
        rows = []
    }

    /// 表示の内容と選択と重ね合わせを捨て、段階を変えます。
    ///
    /// 責務: まとめ・一覧・注記・出典・選択・重ね合わせを空にし、指定の段階にします(セッションと絞り込みは保持します)。
    /// - Parameter status: 新しい段階。
    private func clearContent(status: SessionRoadRegulationReviewStatus) {
        rows = []
        state = SessionRoadRegulationReviewState(sessionID: state.sessionID, status: status, filter: state.filter)
    }

    /// 照合を始めます。
    ///
    /// 責務: 前の照合を取り消し、入力を覚えて `evaluating` にし、内容と重ね合わせを空にして新しい世代の照合を起動します。
    /// - Parameters:
    ///   - sessionID: 対象のセッション ID。
    ///   - rawLog: 照合の時点の Raw の状態。
    private func beginEvaluation(sessionID: ConnectionSessionID, rawLog: SessionRoadRegulationRawLogAvailability) {
        cancelEvaluation()
        evaluatedRawLog = rawLog
        clearContent(status: .evaluating)
        let generation = generation
        task = Task { [weak self] in
            await self?.performEvaluation(sessionID: sessionID, rawLog: rawLog, generation: generation)
        }
    }

    /// 1回の照合を行い、世代が変わっていなければ結果を反映します。
    ///
    /// 責務: ポートから結果を受け取り、取消は状態を変えずに戻り、それ以外の失敗は `failed` に、結果のない段階はその段階にし、
    /// 照合できた時は内容を作って反映します。
    /// - Parameters:
    ///   - sessionID: 対象のセッション ID。
    ///   - rawLog: 照合の時点の Raw の状態。
    ///   - generation: この照合の世代。
    private func performEvaluation(sessionID: ConnectionSessionID, rawLog: SessionRoadRegulationRawLogAvailability, generation: Int) async {
        defer {
            if self.generation == generation {
                task = nil
            }
        }
        let result: SessionRoadRegulationReviewResult
        do {
            result = try await reviewPort.review(sessionID: sessionID)
        } catch is CancellationError {
            return
        } catch {
            if self.generation == generation {
                state.status = .failed
            }
            return
        }
        guard self.generation == generation else {
            return
        }
        switch result {
        case .noTrack:
            state.status = .noTrack
        case .noRegulationData:
            state.status = .noRegulationData
        case .reviewed(let review):
            await buildContent(for: review, rawLog: rawLog, generation: generation)
        }
    }

    /// 照合の結果から表示の内容をメインの外で作り、世代が変わっていなければ反映します。
    ///
    /// 責務: 内容の組み立てを `Task.detached` へ渡して取消を伝え、戻った時に世代を照合して内容を反映します。
    /// - Parameters:
    ///   - review: 照合の結果。
    ///   - rawLog: 照合の時点の Raw の状態。
    ///   - generation: この照合の世代。
    private func buildContent(for review: SessionRoadRegulationReview, rawLog: SessionRoadRegulationRawLogAvailability, generation: Int) async {
        let contentBuilder = contentBuilder
        let builder = Task.detached(priority: .userInitiated) { () -> SessionRoadRegulationReviewContent? in
            Task.isCancelled ? nil : contentBuilder.content(for: review, rawLog: rawLog)
        }
        let content = await withTaskCancellationHandler { await builder.value } onCancel: { builder.cancel() }
        guard let content, self.generation == generation else {
            return
        }
        applyContent(content)
    }

    /// 作った内容を状態へ反映します。
    ///
    /// 責務: 行を覚え、まとめ・注記・出典を入れ、今の絞り込みで一覧を作り、選択なしの重ね合わせを作って `loaded` にします。
    /// - Parameter content: 結果から作った内容。
    private func applyContent(_ content: SessionRoadRegulationReviewContent) {
        rows = content.rows
        state.summaries = content.summaries
        state.notices = content.notices
        state.attribution = content.attribution
        state.sections = sectionBuilder.sections(for: rows, filter: state.filter)
        state.selectedRowID = nil
        rebuildOverlays()
        state.status = .loaded
    }

    /// 今の行と選択から重ね合わせを作り直します。
    ///
    /// 責務: 重ね合わせの部品に行と選択中の行の id を渡し、結果を状態へ入れます。
    private func rebuildOverlays() {
        state.overlays = overlayBuilder.overlays(for: rows, selectedRowID: state.selectedRowID)
    }

    /// 待ちの段階に対応する表示の段階を返します。
    ///
    /// 責務: `waitingForRoute` / `routeUnavailable` / `waitingForRawLog` を同名の段階へ写します(`ready` は呼ばれない前提で `evaluating` を返します)。
    /// - Parameter readiness: 準備の段階。
    /// - Returns: 表示の段階。
    private static func waitingStatus(for readiness: SessionRoadRegulationReviewReadiness) -> SessionRoadRegulationReviewStatus {
        switch readiness {
        case .waitingForRoute:
            .waitingForRoute
        case .routeUnavailable:
            .routeUnavailable
        case .waitingForRawLog:
            .waitingForRawLog
        case .ready:
            .evaluating
        }
    }
}
