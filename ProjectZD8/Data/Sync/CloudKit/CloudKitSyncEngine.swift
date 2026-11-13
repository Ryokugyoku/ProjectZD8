import CloudKit
import Foundation

/// `CKSyncEngine` でプライベートデータベースのカスタムゾーンとローカルのテーブルを同期します。
///
/// 判断の大半は純粋な部品(`SyncLocalStore`・`SyncRemoteChangeApplier`・`CloudKitRecordMapper`・
/// `SyncConflictResolver`・`CloudKitSyncErrorClassifier`)にあり、この型はCloudKitとの受け渡しだけを担います。
/// `CKContainer` はエンタイトルメントが無いと生成時に異常終了するため、`start()` まで生成しません。
///
/// セッションのRawアーカイブはエンジン管理外のアーカイブゾーンにあります。エンジンには属性ゾーンだけを取得させ、
/// アーカイブの保存・削除はこの型が `CloudKitArchiveZoneClient` で直接行います(1件ずつ作成・送信します)。
actor CloudKitSyncEngine: CloudSyncPort, CKSyncEngineDelegate {
    private let containerIdentifier: String
    private let localStore: SyncLocalStore
    private let applier: SyncRemoteChangeApplier
    private let archives: SyncSessionArchiveStore
    private let stateStore: SyncEngineStateStore
    private let eraser: SyncLocalDataEraser
    private let monitor: SyncLocalChangeMonitor
    private let staging: SyncArchiveStaging
    private let mapper: CloudKitRecordMapper
    private let archiveMapper = CloudKitArchiveRecordMapper()
    private let archiveIndex: SyncArchiveIndex
    private let classifier = CloudKitSyncErrorClassifier()
    private let codec = SessionArchiveCodec()
    private let broadcaster = CloudSyncStatusBroadcaster()
    private let now: @Sendable () -> Date

    private var container: CKContainer?
    private var engine: CKSyncEngine?
    private var observationTasks: [Task<Void, Never>] = []
    private var isScanScheduled = false
    /// 進行中の送受信の間に起きた失敗です。送受信の終了時に状態へ反映します。
    private var operationFailure: CloudSyncFailure?
    /// アーカイブの保存・削除の処理が動いているかどうかです。
    private var isArchiveMaintenanceRunning = false
    /// 処理中に次の処理が要求されたかどうかです。
    private var isArchiveMaintenanceRequested = false

    /// 同期の間隔を詰めすぎないよう、ローカル変更の検知から走査までに置く待ち時間です。
    private static let scanDelay: Duration = .milliseconds(500)

    /// 責務: 共有データベースと写真ストアを同期するエンジンを生成します。CloudKitにはまだ触れません。
    /// - Parameters:
    ///   - database: アプリ全体で共有するデータベース。
    ///   - photoFiles: 写真の画像ファイルの保存先。
    ///   - containerIdentifier: CloudKitコンテナの識別子。
    ///   - staging: アップロード中のアーカイブの一時置き場。
    ///   - now: 現在時刻。
    init(
        database: AppDatabase,
        photoFiles: PhotoFileStore,
        containerIdentifier: String = CloudKitSyncConfiguration.containerIdentifier,
        staging: SyncArchiveStaging = SyncArchiveStaging(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.containerIdentifier = containerIdentifier
        self.localStore = SyncLocalStore(database: database, photoFiles: photoFiles)
        self.applier = SyncRemoteChangeApplier(database: database, photoFiles: photoFiles)
        self.archives = SyncSessionArchiveStore(database: database)
        self.stateStore = SyncEngineStateStore(database: database)
        self.eraser = SyncLocalDataEraser(database: database, photoFiles: photoFiles)
        self.monitor = SyncLocalChangeMonitor(database: database)
        self.staging = staging
        self.mapper = CloudKitRecordMapper(zoneID: CloudKitSyncConfiguration.zoneID)
        self.archiveIndex = SyncArchiveIndex(database: database)
        self.now = now
    }

    // MARK: - CloudSyncPort

    /// 責務: コンテナと同期エンジンを用意し、ローカル変更の監視とアカウント変化の監視を始めます。
    func start() async {
        guard container == nil else { return }
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        try? FileManager.default.removeItem(at: staging.directory) // 前回の送信途中で残った一時ファイル
        await refreshAccountStatus()

        let serialization: CKSyncEngine.State.Serialization?
        do {
            serialization = try stateStore.load().map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        } catch {
            // 読めない状態は捨てて最初から同期し直します(全件を取得し直すだけで、データは失いません)。
            try? stateStore.clear()
            serialization = nil
        }
        makeEngine(container: container, stateSerialization: serialization)
        enqueueLocalChanges()
        requestArchiveMaintenance()

        let changes = monitor.changes()
        observationTasks.append(Task { [weak self] in
            for await _ in changes {
                await self?.localChangeDetected()
            }
        })
        observationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await self?.refreshAccountStatus()
            }
        })
    }

    /// 責務: 現在の同期状態を最初に流し、以後の変化を流します。
    nonisolated func statusUpdates() -> AsyncStream<CloudSyncStatus> {
        broadcaster.stream()
    }

    /// 責務: 未送信の変更を登録し直してから、リモート変更の取得(属性ゾーンのみ)と送信を今すぐ行い、
    /// アーカイブの保存・削除の処理も起動します。
    func syncNow() async throws {
        let engine = try availableEngine()
        enqueueLocalChanges()
        do {
            try await engine.fetchChanges(CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([mapper.zoneID])))
            try await engine.sendChanges()
        } catch {
            throw classifier.failure(for: error)
        }
        requestArchiveMaintenance()
    }

    /// 責務: `cloudOnly` のセッションのアーカイブレコードをアーカイブゾーンから直接ダウンロード・検証し、ローカルへ復元します。
    func restoreSessionArchive(_ id: SessionID, progress: @escaping @Sendable (Double) -> Void) async throws {
        let engine = try availableEngine()
        let name = id.rawValue.uuidString.lowercased()
        do {
            guard let target = try archives.restoreTarget(sessionID: name) else { throw CloudSyncFailure.notFound }
            if target.rawAvailability == .local {
                progress(1)
                return
            }
            let download = try await CloudKitArchiveDownloader(database: engine.database).download(recordID: archiveMapper.recordID(sessionID: name), progress: progress)
            let archive = try codec.decode(download.data, expectedDigest: download.digest)
            guard archive.session.id == id else { throw CloudSyncFailure.integrity }
            try archives.restore(archive)
            progress(1)
        } catch {
            throw classifier.failure(for: error)
        }
    }

    /// 責務: iCloudの属性ゾーンとアーカイブゾーンを削除してから、この端末の全ユーザーデータと同期状態を消去します。
    ///
    /// iCloudアカウントが無い場合は、iCloud上にデータが無いのでこの端末だけを消去します。
    func eraseAllData() async throws {
        if case .unavailable(.noAccount) = broadcaster.status {
            try eraseLocal()
            return
        }
        let engine = try availableEngine()
        guard let container else { throw CloudSyncFailure.other }
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
        await engine.cancelOperations()
        do {
            let zoneIDs = [CloudKitSyncConfiguration.zoneID, CloudKitSyncConfiguration.archiveZoneID]
            let result = try await engine.database.modifyRecordZones(saving: [], deleting: zoneIDs)
            for zoneID in zoneIDs {
                if case .failure(let error) = result.deleteResults[zoneID], (error as? CKError)?.code != .zoneNotFound {
                    throw error
                }
            }
        } catch {
            throw classifier.failure(for: error)
        }
        try eraseLocal()
        makeEngine(container: container, stateSerialization: nil)
    }

    // MARK: - CKSyncEngineDelegate

    /// 責務: 同期エンジンのイベントを、状態保存・アカウント処理・取得結果の適用・送信結果の記録へ振り分けます。
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            do {
                try stateStore.save(try JSONEncoder().encode(update.stateSerialization))
            } catch {
                noteFailure(.other)
            }
        case .accountChange(let change):
            await handleAccountChange(change, syncEngine: syncEngine)
        case .fetchedDatabaseChanges(let changes):
            handleFetchedDatabaseChanges(changes, syncEngine: syncEngine)
        case .fetchedRecordZoneChanges(let changes):
            handleFetchedRecordZoneChanges(changes)
        case .sentDatabaseChanges(let changes):
            for failure in changes.failedZoneSaves {
                noteFailure(classifier.failure(for: failure.error))
            }
        case .sentRecordZoneChanges(let changes):
            handleSentRecordZoneChanges(changes, syncEngine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            broadcaster.update { $0.operationStarted() }
        case .didFetchChanges, .didSendChanges:
            let failure = operationFailure
            operationFailure = nil
            let date = now()
            broadcaster.update { $0.operationFinished(at: date, failure: failure) }
        case .didFetchRecordZoneChanges(let result):
            if let error = result.error { noteFailure(classifier.failure(for: error)) }
        case .willFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    /// 責務: エンジンの取得範囲を属性ゾーンだけに絞ります(アーカイブゾーンのアセットを自動ダウンロードさせません)。
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        options.scope = CloudKitSyncFetchScope.restrictedToMainZone(options.scope, mainZoneID: mapper.zoneID)
        options.prioritizedZoneIDs = options.prioritizedZoneIDs.filter { $0 == mapper.zoneID }
        return options
    }

    /// 責務: 送信待ちの変更から、親を先にした次の送信バッチを作ります。
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let localPending: [SyncPendingChange]
        do {
            localPending = try localStore.pendingChanges()
        } catch {
            noteFailure(.other)
            return nil
        }
        let types = Dictionary(localPending.map { ($0.recordName, $0.recordType) }, uniquingKeysWith: { first, _ in first })
        let changes = syncEngine.state.pendingRecordZoneChanges
            .filter { scope.contains($0) }
            .sorted { Self.sendRank($0, types: types) < Self.sendRank($1, types: types) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.recordToSend(recordID, recordType: types[recordID.recordName], syncEngine: syncEngine)
        }
    }

    // MARK: - 送信

    /// 責務: 1件の保存待ちレコードを作ります。送るものが無ければ保留中の変更から外します。
    private func recordToSend(_ recordID: CKRecord.ID, recordType: SyncRecordType?, syncEngine: CKSyncEngine) -> CKRecord? {
        let name = recordID.recordName
        do {
            guard let type = try recordType ?? localStore.recordType(forRecordName: name),
                  let outgoing = try localStore.outgoingRecord(recordType: type, recordName: name) else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return mapper.record(for: outgoing)
        } catch {
            // 作れないレコードは外します。次のローカル変更の走査か起動時に再登録されます。
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            noteFailure(.other)
            return nil
        }
    }

    /// 責務: 送信結果を記録し、失敗したレコードを種類に応じて再送・競合解決します。
    private func handleSentRecordZoneChanges(_ changes: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        for record in changes.savedRecords {
            guard let type = SyncRecordType(rawValue: record.recordType) else { continue }
            let name = record.recordID.recordName
            guard let sentModifiedAt: Int64 = record["modifiedAt"] else { continue }
            do {
                let exists = try localStore.markSaved(
                    recordType: type,
                    recordName: name,
                    systemFields: CloudKitRecordMapper.encodeSystemFields(of: record),
                    sentModifiedAt: sentModifiedAt
                )
                if !exists {
                    // 送信中にローカルで消された行は、サーバーからも消します。
                    syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(record.recordID)])
                }
            } catch {
                noteFailure(.other)
            }
        }

        for failed in changes.failedRecordSaves {
            let record = failed.record
            guard let type = SyncRecordType(rawValue: record.recordType) else { continue }
            let name = record.recordID.recordName
            let retry = CKSyncEngine.PendingRecordZoneChange.saveRecord(record.recordID)
            do {
                switch classifier.handling(forSaveError: failed.error) {
                case .resolveConflict:
                    guard let serverRecord = failed.error.serverRecord else {
                        syncEngine.state.add(pendingRecordZoneChanges: [retry])
                        continue
                    }
                    let outcome = try applier.apply(
                        try mapper.payload(from: serverRecord),
                        systemFields: CloudKitRecordMapper.encodeSystemFields(of: serverRecord)
                    )
                    if outcome == .keptLocal { syncEngine.state.add(pendingRecordZoneChanges: [retry]) }
                case .recreateZone:
                    try localStore.replaceSystemFields(recordType: type, recordName: name, systemFields: nil)
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudKitSyncConfiguration.zoneID))])
                    syncEngine.state.add(pendingRecordZoneChanges: [retry])
                case .recreateRecord:
                    try localStore.replaceSystemFields(recordType: type, recordName: name, systemFields: nil)
                    syncEngine.state.add(pendingRecordZoneChanges: [retry])
                case .retry:
                    syncEngine.state.add(pendingRecordZoneChanges: [retry])
                case .automaticRetry:
                    noteFailure(classifier.failure(for: failed.error))
                case .report(let failure):
                    noteFailure(failure)
                }
            } catch {
                noteFailure(.other)
            }
        }

        for recordID in changes.deletedRecordIDs {
            confirmDeletion(recordID)
        }
        for (recordID, error) in changes.failedRecordDeletes {
            switch error.code {
            case .unknownItem, .zoneNotFound, .userDeletedZone:
                confirmDeletion(recordID)
            default:
                noteFailure(classifier.failure(for: error))
            }
        }
        if !changes.deletedRecordIDs.isEmpty || !changes.failedRecordDeletes.isEmpty {
            requestArchiveMaintenance()
        }
    }

    /// 責務: サーバーでの削除完了をローカルへ反映します。
    private func confirmDeletion(_ recordID: CKRecord.ID) {
        do {
            guard let type = try localStore.recordType(forRecordName: recordID.recordName) else { return }
            try localStore.markDeletionConfirmed(recordType: type, recordName: recordID.recordName)
        } catch {
            noteFailure(.other)
        }
    }

    // MARK: - 取得

    /// 責務: 取得したレコードの変更と削除をローカルへ適用します。車両を先に適用します。
    private func handleFetchedRecordZoneChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        let records = changes.modifications
            .map(\.record)
            .filter { $0.recordID.zoneID == mapper.zoneID }
            .sorted { (SyncRecordType(rawValue: $0.recordType)?.sendOrder ?? .max) < (SyncRecordType(rawValue: $1.recordType)?.sendOrder ?? .max) }
        for record in records {
            do {
                let payload = try mapper.payload(from: record)
                var image: Data?
                if case .photo = payload, let url = (record[CloudKitRecordMapper.Field.image] as? CKAsset)?.fileURL {
                    image = try Data(contentsOf: url)
                }
                try applier.apply(payload, systemFields: CloudKitRecordMapper.encodeSystemFields(of: record), photoImage: image)
            } catch {
                noteFailure(.other)
            }
        }
        for deletion in changes.deletions where deletion.recordID.zoneID == mapper.zoneID {
            guard let type = SyncRecordType(rawValue: deletion.recordType) else { continue }
            do {
                try applier.applyDeletion(recordType: type, recordName: deletion.recordID.recordName)
            } catch {
                noteFailure(.other)
            }
        }
        if !changes.deletions.isEmpty { requestArchiveMaintenance() }
    }

    /// 責務: ゾーンの削除やリセットをローカルへ反映します。
    private func handleFetchedDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges, syncEngine: CKSyncEngine) {
        for deletion in changes.deletions where deletion.zoneID == mapper.zoneID {
            do {
                switch deletion.reason {
                case .encryptedDataReset:
                    // 暗号化キーのリセットでサーバーのデータが失われた。ローカルを全て送り直します
                    // (Rawがローカルのセッションはアーカイブも送り直します)。
                    try localStore.resetForReupload()
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: mapper.zoneID))])
                    enqueueLocalChanges()
                    requestArchiveMaintenance()
                default:
                    // 他の端末で全データ削除された(またはユーザーがiCloud設定から削除した)。
                    try eraser.eraseAll()
                }
            } catch {
                noteFailure(.other)
            }
        }
    }

    // MARK: - アカウント

    /// 責務: サインインでは全ローカルデータを送信待ちにし、サインアウトや切り替えではローカルデータと同期状態を消去します。
    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange, syncEngine: CKSyncEngine) async {
        do {
            switch change.changeType {
            case .signIn:
                try localStore.resetForReupload()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: mapper.zoneID))])
                enqueueLocalChanges()
                requestArchiveMaintenance()
            case .signOut, .switchAccounts:
                try eraseLocal()
                if let container { makeEngine(container: container, stateSerialization: nil) }
            @unknown default:
                break
            }
        } catch {
            noteFailure(.other)
        }
        await refreshAccountStatus()
    }

    /// 責務: iCloudアカウントの状態を取得し、同期状態へ反映します。
    private func refreshAccountStatus() async {
        guard let container else { return }
        let reason: CloudSyncUnavailableReason?
        do {
            reason = Self.unavailableReason(for: try await container.accountStatus())
        } catch {
            reason = .temporarilyUnavailable
        }
        broadcaster.update { $0.accountChanged(unavailableReason: reason) }
        if reason == nil { requestArchiveMaintenance() }
    }

    /// 責務: CloudKitのアカウント状態を同期を利用できない理由へ変換します。利用できれば `nil` です。
    static func unavailableReason(for status: CKAccountStatus) -> CloudSyncUnavailableReason? {
        switch status {
        case .available: nil
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .couldNotDetermine, .temporarilyUnavailable: .temporarilyUnavailable
        @unknown default: .temporarilyUnavailable
        }
    }

    // MARK: - 内部

    /// 責務: 同期エンジンを生成します。状態が無ければゾーンの作成を予約します。
    private func makeEngine(container: CKContainer, stateSerialization: CKSyncEngine.State.Serialization?) {
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        if stateSerialization == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: mapper.zoneID))])
        }
        self.engine = engine
    }

    /// 責務: 同期を利用できる時の同期エンジンを返します。
    private func availableEngine() throws -> CKSyncEngine {
        guard let engine else { throw CloudSyncFailure.other }
        if case .unavailable = broadcaster.status { throw CloudSyncFailure.other }
        return engine
    }

    /// 責務: ローカルのテーブルから導いた未送信の変更のうち、エンジンに未登録のものを登録します。
    private func enqueueLocalChanges() {
        guard let engine else { return }
        do {
            let registered = Set(engine.state.pendingRecordZoneChanges)
            let changes = try localStore.pendingChanges()
                .map { change -> CKSyncEngine.PendingRecordZoneChange in
                    let recordID = mapper.recordID(name: change.recordName)
                    return change.kind == .save ? .saveRecord(recordID) : .deleteRecord(recordID)
                }
                .filter { !registered.contains($0) }
            if !changes.isEmpty {
                engine.state.add(pendingRecordZoneChanges: changes)
            }
        } catch {
            noteFailure(.other)
        }
    }

    /// 責務: ローカル変更の検知を受け、少し待ってからまとめて走査します。
    private func localChangeDetected() {
        guard !isScanScheduled else { return }
        isScanScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.scanDelay)
            await self?.runScheduledScan()
        }
    }

    /// 責務: 予約した走査を実行します。
    private func runScheduledScan() {
        isScanScheduled = false
        enqueueLocalChanges()
        requestArchiveMaintenance()
    }

    // MARK: - アーカイブ

    /// 責務: アーカイブの削除と保存の処理を要求します。動作中なら終了後にもう一巡します。
    private func requestArchiveMaintenance() {
        isArchiveMaintenanceRequested = true
        guard !isArchiveMaintenanceRunning else { return }
        isArchiveMaintenanceRunning = true
        Task { await self.runArchiveMaintenance() }
    }

    /// 責務: 要求が無くなるまで、削除待ちのアーカイブの削除と、未アップロードのアーカイブの保存を繰り返します。
    private func runArchiveMaintenance() async {
        while isArchiveMaintenanceRequested {
            isArchiveMaintenanceRequested = false
            guard let container, engine != nil else { break }
            if case .unavailable = broadcaster.status { break }
            let client = CloudKitArchiveZoneClient(database: container.privateCloudDatabase, mapper: archiveMapper)
            await drainArchiveDeletions(client)
            await uploadPendingArchives(client)
        }
        isArchiveMaintenanceRunning = false
    }

    /// 責務: 削除待ちのアーカイブを削除します。失敗したものは列に残し、次の同期で再試行します。
    private func drainArchiveDeletions(_ client: CloudKitArchiveZoneClient) async {
        do {
            try archiveIndex.reconcile()
            let queued = try archiveIndex.queuedDeletions().map(\.sessionID)
            guard !queued.isEmpty else { return }
            let outcome = await client.delete(sessionIDs: queued)
            let completed = queued.filter { outcome[$0] == true }
            try archiveIndex.deletionsCompleted(sessionIDs: completed)
            if completed.count < queued.count { noteFailure(.network) }
        } catch {
            noteFailure(.other)
        }
    }

    /// 責務: 未アップロードのアーカイブを1件ずつ作って保存し、成功したら検証値を記録して属性レコードを送信待ちにします。
    ///
    /// 同時に保持するアーカイブは1件だけです。失敗したセッションはこの巡回では飛ばし、次の要求で再試行します。
    private func uploadPendingArchives(_ client: CloudKitArchiveZoneClient) async {
        let sessionIDs: [String]
        do {
            sessionIDs = try localStore.pendingArchiveUploads()
        } catch {
            noteFailure(.other)
            return
        }
        for sessionID in sessionIDs {
            if case .unavailable = broadcaster.status { return }
            do {
                guard let staged = try stageArchive(sessionID: sessionID) else { continue }
                defer { staging.remove(sessionID: sessionID) }
                try await client.upload(sessionID: sessionID, vehicleID: staged.vehicleID, digest: staged.digest, fileURL: staged.fileURL)
                try localStore.markArchiveUploaded(sessionID: sessionID, vehicleID: staged.vehicleID, digest: staged.digest)
                enqueueLocalChanges()
            } catch {
                noteFailure(classifier.failure(for: error))
            }
        }
    }

    /// 責務: 1件のアーカイブを作って一時ファイルへ書き出します。メモリ上のアーカイブはこの関数を抜けると解放されます。
    private func stageArchive(sessionID: String) throws -> (fileURL: URL, digest: String, vehicleID: String)? {
        guard let archive = try archives.makeArchive(sessionID: sessionID) else { return nil }
        let encoded = try codec.encode(archive)
        let url = try staging.write(encoded, sessionID: sessionID)
        return (url, encoded.digest, archive.session.vehicleID.rawValue.uuidString.lowercased())
    }

    /// 責務: この端末の全ユーザーデータと同期状態を消去します。
    private func eraseLocal() throws {
        try eraser.eraseAll()
    }

    /// 責務: 送受信中の失敗を記録します。送受信中でなければ直ちに状態へ反映します。
    private func noteFailure(_ failure: CloudSyncFailure) {
        if case .syncing = broadcaster.status {
            operationFailure = failure
        } else {
            broadcaster.update { $0.recordFailure(failure) }
        }
    }

    /// 責務: 送信順の順位を返します。保存は親から、削除は保存の後に子から並べます。
    private static func sendRank(_ change: CKSyncEngine.PendingRecordZoneChange, types: [String: SyncRecordType]) -> Int {
        switch change {
        case .saveRecord(let id):
            return types[id.recordName]?.sendOrder ?? 9
        case .deleteRecord(let id):
            return 20 - (types[id.recordName]?.sendOrder ?? 0)
        @unknown default:
            return 99
        }
    }
}
