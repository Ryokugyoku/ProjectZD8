import Foundation
import Observation

/// 交通規制データの管理画面の操作を、ユースケースの呼び出しと状態の遷移へ変換するモデルです。
///
/// - 判定と遷移の規則は `RoadRegulationSettingsState` が持ち、このモデルは Action をユースケースへつなぐだけです。
/// - 画面を開いた時(`appeared`)は手元の版を読み、残骸を掃除するだけで、通信しません。一覧は「更新を確認」の時だけ取りに行きます。
/// - 取り込み・確認・削除・掃除はメインスレッドの外で行います。モデルが破棄されると、実行中の Task をすべて取り消します。
/// - 取り込みは、先に始めた掃除と削除が終わってから始めます(取り込み中の版を掃除で消さないため)。
@MainActor
@Observable
final class RoadRegulationSettingsModel {
    /// 画面が描画する状態。
    private(set) var state: RoadRegulationSettingsState

    /// 有効な版の読み取り。
    @ObservationIgnored private let list: ListRoadRegulationDatasetsUseCase
    /// 取り込み。
    @ObservationIgnored private let importer: ImportRoadRegulationDatasetUseCase
    /// 削除。
    @ObservationIgnored private let remover: RemoveRoadRegulationDatasetUseCase
    /// 一覧の取得。
    @ObservationIgnored private let catalog: FetchRoadRegulationCatalogUseCase
    /// 残骸の掃除。
    @ObservationIgnored private let purge: PurgeRoadRegulationLeftoversUseCase
    /// 現在時刻。
    @ObservationIgnored private let now: () -> Date
    /// 失敗の分類。
    @ObservationIgnored private let classifier = RoadRegulationImportErrorClassifier()
    /// 実行中の取り込み。
    @ObservationIgnored private var importTask: Task<Void, Never>?
    /// 実行中の一覧の確認。
    @ObservationIgnored private var catalogTask: Task<Void, Never>?
    /// 実行中の削除。
    @ObservationIgnored private var removalTask: Task<Void, Never>?
    /// 実行中の掃除。
    @ObservationIgnored private var purgeTask: Task<Void, Never>?

    /// ユースケースを受け取り、版を読む前の状態で始めます。
    ///
    /// 責務: 画面の操作に使うユースケースと時刻を保持します(版は `appeared` で読みます)。
    /// - Parameters:
    ///   - list: 有効な版の読み取り。
    ///   - importer: 取り込み。
    ///   - remover: 削除。
    ///   - catalog: 一覧の取得。
    ///   - purge: 残骸の掃除。
    ///   - now: 現在時刻。
    init(
        list: ListRoadRegulationDatasetsUseCase,
        importer: ImportRoadRegulationDatasetUseCase,
        remover: RemoveRoadRegulationDatasetUseCase,
        catalog: FetchRoadRegulationCatalogUseCase,
        purge: PurgeRoadRegulationLeftoversUseCase,
        now: @escaping () -> Date = Date.init
    ) {
        self.list = list
        self.importer = importer
        self.remover = remover
        self.catalog = catalog
        self.purge = purge
        self.now = now
        state = .initial(datasets: [])
    }

    /// 実行中の Task をすべて取り消します。
    deinit {
        importTask?.cancel()
        catalogTask?.cancel()
        removalTask?.cancel()
        purgeTask?.cancel()
    }

    /// 画面の操作を受け取ります。
    ///
    /// 責務: 1件の操作を、状態の遷移とユースケースの呼び出しへ振り分けます。
    /// - Parameter action: 画面から送られた操作。
    func send(_ action: RoadRegulationSettingsAction) {
        switch action {
        case .appeared: appear()
        case .checkUpdatesRequested: checkUpdates()
        case let .downloadRequested(prefecture): startImport(of: prefecture)
        case .cancelRequested: cancelImport()
        case let .removeRequested(prefecture): state.requestRemoval(of: prefecture)
        case .removeConfirmed: confirmRemoval()
        case .removeCancelled: state.pendingRemoval = nil
        case .errorDismissed: state.presentedError = nil
        }
    }

    /// 画面を開いた時に、手元の版を読み、取り込み中でなければ残骸を掃除します。
    ///
    /// 責務: 版を読み直し、掃除をメインスレッドの外で1つだけ走らせます(通信はしません)。
    private func appear() {
        reloadDatasets()
        guard state.importingPrefecture == nil, purgeTask == nil else { return }
        let purge = purge
        purgeTask = Task { [weak self] in
            do {
                try await purge.execute()
            } catch {
                self?.present(error)
            }
            self?.purgeTask = nil
        }
    }

    /// 一覧の確認を始めます。
    ///
    /// 責務: 確認中でなければ確認中にし、結果を状態へ反映する Task を走らせます。
    private func checkUpdates() {
        guard state.catalogStatus != .checking else { return }
        state.setCatalogStatus(.checking)
        let catalog = catalog
        catalogTask = Task { [weak self] in
            do {
                let result = try await catalog.execute()
                self?.catalogChecked(result)
            } catch {
                self?.catalogFailed(error)
            }
        }
    }

    /// 県の取り込みを始めます。
    ///
    /// 責務: 状態を取り込み中にし、先の掃除と削除を待ってから事象の流れを状態へ反映する Task を走らせます。
    /// - Parameter prefecture: 取り込む県。
    private func startImport(of prefecture: JapanesePrefectureCode) {
        guard state.beginImport(of: prefecture) else { return }
        let precedingTasks = [purgeTask, removalTask].compactMap { $0 }
        let events = { [importer, catalog = state.catalogStatus.catalog] in importer.events(for: prefecture, catalog: catalog) }
        importTask = Task { [weak self] in
            for task in precedingTasks {
                await task.value
            }
            guard !Task.isCancelled else { return }
            await self?.consume(events())
        }
    }

    /// 取り込みの事象の流れを最後まで読み、状態へ反映します。
    ///
    /// 責務: 進捗と完了を反映し、失敗と途中で終わった流れを状態へ反映します。取り消された後は何も反映しません。
    /// - Parameter events: 取り込みの事象の流れ。
    private func consume(_ events: AsyncThrowingStream<RoadRegulationImportEvent, any Error>) async {
        do {
            for try await event in events {
                guard !Task.isCancelled else { return }
                apply(event)
            }
            guard !Task.isCancelled else { return }
            state.cancelImport()
        } catch {
            guard !Task.isCancelled else { return }
            importFailed(error)
        }
        importTask = nil
    }

    /// 取り込みの事象を1件反映します。
    ///
    /// 責務: 進捗なら段階を、完了なら新しい版を状態へ反映します。
    /// - Parameter event: 取り込みの事象。
    private func apply(_ event: RoadRegulationImportEvent) {
        switch event {
        case let .progress(phase):
            state.updateImport(phase)
        case let .completed(dataset):
            state.completeImport(with: dataset)
        }
    }

    /// 取り込みを中止します。
    ///
    /// 責務: 実行中の取り込みを取り消し、状態をすぐ取り込み前の表示へ戻します(後始末は取り込み側が行います)。
    private func cancelImport() {
        importTask?.cancel()
        importTask = nil
        state.cancelImport()
    }

    /// 削除の確認を受けて、削除を走らせます。
    ///
    /// 責務: 削除する県が決まれば、メインスレッドの外で削除し、結果を状態へ反映します。
    private func confirmRemoval() {
        guard let prefecture = state.confirmRemoval() else { return }
        let remover = remover
        removalTask = Task { [weak self] in
            do {
                try await remover.execute(prefecture: prefecture)
                self?.removalCompleted(prefecture)
            } catch {
                self?.present(error)
            }
            self?.removalTask = nil
        }
    }

    /// 削除の完了を反映します。
    ///
    /// 責務: 行を未取得に戻し、手元の版を読み直します。
    /// - Parameter prefecture: 削除した県。
    private func removalCompleted(_ prefecture: JapanesePrefectureCode) {
        state.completeRemoval(of: prefecture)
        reloadDatasets()
    }

    /// 手元の有効な版を読み直します。
    ///
    /// 責務: 版の一覧を状態へ反映し、読めなければエラーを出します(空の一覧に潰しません)。
    private func reloadDatasets() {
        do {
            state.replaceDatasets(try list.execute())
        } catch {
            present(error)
        }
    }

    /// 一覧の確認の成功を反映します。
    ///
    /// 責務: 確認した時刻と一覧を状態へ入れます。
    /// - Parameter result: 確認した一覧。
    private func catalogChecked(_ result: RoadRegulationCatalog) {
        state.setCatalogStatus(.checked(at: now(), catalog: result))
        catalogTask = nil
    }

    /// 一覧の確認の失敗を反映します。
    ///
    /// 責務: 失敗を確認の状態に入れます。取り消しなら未確認に戻します。
    /// - Parameter error: 失敗。
    private func catalogFailed(_ error: any Error) {
        let importError = classifier.importError(for: error, fallback: .catalogUnavailable)
        state.setCatalogStatus(importError.map(RoadRegulationCatalogCheckStatus.failed) ?? .notChecked)
        catalogTask = nil
    }

    /// 取り込みの失敗を反映します。
    ///
    /// 責務: 取り消しなら中止として、それ以外は失敗として状態へ反映します。
    /// - Parameter error: 失敗。
    private func importFailed(_ error: any Error) {
        guard let importError = classifier.importError(for: error, fallback: .storageUnavailable) else {
            state.cancelImport()
            return
        }
        state.failImport(importError)
    }

    /// 失敗を画面に出します。
    ///
    /// 責務: 取り消し以外の失敗を、取り込みのエラーとして画面に出します。
    /// - Parameter error: 失敗。
    private func present(_ error: any Error) {
        guard let importError = classifier.importError(for: error, fallback: .storageUnavailable) else { return }
        state.presentedError = importError
    }
}
