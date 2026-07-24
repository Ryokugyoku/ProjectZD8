import Foundation
import XCTest
@testable import ProjectZD8

/// アカウント単位の接続履歴表示状態を検証します。
@MainActor
final class ConnectionHistoryModelTests: XCTestCase {
    /// 全終了理由と並び順がString Catalogの固定キーへ対応します。
    ///
    /// 責務: 動的補間キーを使わず履歴表示の全選択肢を登録済み固定キーへ変換できることを確認します。
    func testHistoryLocalizationKeysAreFixedCatalogEntries() {
        XCTAssertEqual(
            ConnectionHistoryEndReasonFilter.allCases.map(\.historyLocalizationKey),
            [
                "history.reason.all",
                "history.reason.userDisconnected",
                "history.reason.vehicleNoResponse",
                "history.reason.connectionLost",
                "history.reason.acquisitionFailed",
                "history.reason.superseded",
                "history.reason.accountSignedOut",
                "history.reason.unexpectedTermination"
            ]
        )
        XCTAssertEqual(
            ConnectionHistorySortOrder.allCases.map(\.historyLocalizationKey),
            [
                "history.sort.newest",
                "history.sort.oldest",
                "history.sort.longestDuration",
                "history.sort.shortestDuration"
            ]
        )
        XCTAssertEqual(
            ConnectionSessionEndReason.unexpectedTermination.historyLocalizationKey,
            "history.reason.unexpectedTermination"
        )
    }

    /// 有効化したアカウントの履歴だけを新しい順で公開します。
    ///
    /// 責務: 1件のアカウント変更が対応する履歴一覧へ変換されることを確認します。
    func testAccountActivationLoadsScopedSessions() {
        let older = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 10))
        let newer = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 20))
        let repository = FixedConnectionSessionRepository(sessions: [newer, older])
        let model = ConnectionHistoryModel(repository: repository)

        model.send(.accountIdentifierChanged("account"))

        XCTAssertEqual(model.state.phase, .loaded)
        XCTAssertEqual(model.state.sessions.map(\.id), [newer.id, older.id])
        XCTAssertEqual(model.state.activeSessions.count, 2)
    }

    /// 実行中の同期へ重複更新要求が届いても同じ同期を再起動しません。
    ///
    /// 責務: 長時間Raw取込中の画面再表示が進行中Taskをキャンセルしないことを確認します。
    func testRepeatedRefreshKeepsSingleSynchronizationInFlight() async {
        let repository = MutableConnectionSessionRepository(sessions: [])
        let transferRepository = PausingConnectionSessionTransferRepository()
        let synchronization = SynchronizeConnectionSessionsUseCase(
            sessionRepository: repository,
            rawLogRepository: EmptyConnectionSessionRawLogRepository(),
            sessionErasureRepository: NoOpConnectionSessionErasureRepository(),
            transferRepository: transferRepository,
            role: .iPhone
        )
        let model = ConnectionHistoryModel(
            repository: repository,
            synchronizeSessions: synchronization
        )

        model.send(.accountIdentifierChanged("account"))
        await transferRepository.waitForDeletionRequest()
        model.send(.refreshRequested)
        model.send(.refreshRequested)
        await Task.yield()

        XCTAssertEqual(transferRepository.deletionRequestCount, 1)
        transferRepository.resumeDeletionRequest()
    }

    /// 終了済み履歴が登録車両単位に集約され、中断件数と総時間を保持することを検証します。
    ///
    /// 責務: 複数セッションを車両ID単位の履歴集計へ変換できることを確認します。
    func testClosedSessionsAreGroupedByVehicleWithAttentionSummary() {
        let vehicleID = VehicleID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
        let vehicle = ConnectionSessionVehicle(id: vehicleID, name: "BRZ", displayIdentifier: "ZD8")
        let completed = makeClosedSession(startedAt: 100, duration: 600, reason: .userDisconnected, vehicle: vehicle)
        var completedWithDistance = completed
        completedWithDistance.startingOdometerKilometers = 1_000
        completedWithDistance.endingOdometerKilometers = 1_001.2
        var interrupted = makeClosedSession(startedAt: 200, duration: 120, reason: .vehicleNoResponse, vehicle: vehicle)
        interrupted.startingOdometerKilometers = 1_001.2
        interrupted.endingOdometerKilometers = 1_001.5
        let state = ConnectionHistoryState(phase: .loaded, sessions: [interrupted, completedWithDistance])

        let group = try? XCTUnwrap(state.vehicleGroups.first)

        XCTAssertEqual(state.vehicleGroups.count, 1)
        XCTAssertEqual(group?.sessionCount, 2)
        XCTAssertEqual(group?.interruptedCount, 1)
        XCTAssertEqual(group?.totalDuration, 720)
        XCTAssertEqual(group?.totalDistanceKilometers ?? -.infinity, 1.5, accuracy: 0.000_1)
        XCTAssertEqual(state.interruptedCount, 1)
    }

    /// 走行距離を確定できないセッションを含む車両集計を非対応として保持します。
    ///
    /// 責務: 部分的なA6対応履歴を不完全な総走行距離として合算しないことを確認します。
    func testVehicleDistanceIsUnsupportedWhenAnySessionLacksOdometerBounds() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        var supported = makeClosedSession(startedAt: 100, duration: 60, reason: .userDisconnected, vehicle: vehicle)
        supported.startingOdometerKilometers = 500
        supported.endingOdometerKilometers = 500.4
        let unsupported = makeClosedSession(startedAt: 200, duration: 60, reason: .userDisconnected, vehicle: vehicle)
        let state = ConnectionHistoryState(phase: .loaded, sessions: [unsupported, supported])

        XCTAssertNil(state.vehicleGroups.first?.totalDistanceKilometers)
    }

    /// 日付範囲と終了理由を同時適用して該当セッションだけを残すことを検証します。
    ///
    /// 責務: 複数の絞り込み条件が論理積として適用されることを確認します。
    func testDateAndEndReasonFiltersCompose() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        let normal = makeClosedSession(startedAt: 100_000, duration: 300, reason: .userDisconnected, vehicle: vehicle)
        let matching = makeClosedSession(startedAt: 200_000, duration: 900, reason: .vehicleNoResponse, vehicle: vehicle)
        let tooLate = makeClosedSession(startedAt: 400_000, duration: 600, reason: .vehicleNoResponse, vehicle: vehicle)
        var state = ConnectionHistoryState(phase: .loaded, sessions: [tooLate, matching, normal])
        state.filterStartDate = Date(timeIntervalSince1970: 150_000)
        state.filterEndDate = Date(timeIntervalSince1970: 250_000)
        state.endReasonFilter = .vehicleNoResponse

        let result = state.filteredSessions(for: .registered(vehicle.id))

        XCTAssertEqual(result.map(\.id), [matching.id])
    }

    /// 走行時間による並び順が日時順と独立して適用されることを検証します。
    ///
    /// 責務: 車両別履歴を記録時間の降順へ並べ替えられることを確認します。
    func testDurationSortOrdersLongestFirst() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        let short = makeClosedSession(startedAt: 300, duration: 60, reason: .userDisconnected, vehicle: vehicle)
        let long = makeClosedSession(startedAt: 100, duration: 900, reason: .userDisconnected, vehicle: vehicle)
        var state = ConnectionHistoryState(phase: .loaded, sessions: [short, long])
        state.sortOrder = .longestDuration

        XCTAssertEqual(state.filteredSessions(for: .registered(vehicle.id)).map(\.id), [long.id, short.id])
    }

    /// リセット操作が日付と終了理由だけを初期化し、選択中の並び順を維持することを検証します。
    ///
    /// 責務: 1件の絞り込みリセット操作を期待する履歴状態へ反映できることを確認します。
    func testFilterResetPreservesSortOrder() {
        var state = ConnectionHistoryState()
        state.filterStartDate = Date(timeIntervalSince1970: 100)
        state.filterEndDate = Date(timeIntervalSince1970: 200)
        state.endReasonFilter = .connectionLost
        state.sortOrder = .oldest
        let model = ConnectionHistoryModel(state: state, repository: FixedConnectionSessionRepository(sessions: []))

        model.send(.filtersReset)

        XCTAssertNil(model.state.filterStartDate)
        XCTAssertNil(model.state.filterEndDate)
        XCTAssertEqual(model.state.endReasonFilter, .all)
        XCTAssertEqual(model.state.sortOrder, .oldest)
    }

    /// ユーザーが意図した停止の確認後は警告件数から外し、観測理由を保持します。
    ///
    /// 責務: 接続喪失セッションの確認操作を正式データ状態と元終了理由の保持へ変換できることを確認します。
    func testStopReviewAcceptsUserInitiatedStopWithoutReplacingObservedReason() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        let session = makeClosedSession(startedAt: 100, duration: 60, reason: .connectionLost, vehicle: vehicle)
        let repository = MutableConnectionSessionRepository(sessions: [session])
        let model = ConnectionHistoryModel(
            repository: repository,
            reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase(repository: repository)
        )
        model.send(.accountIdentifierChanged("account"))

        model.send(.stopReviewRequested(session.id))
        XCTAssertEqual(model.state.stopReviewPrompt?.observedReason, .connectionLost)
        model.send(.stopReviewConfirmed)

        let reviewed = model.state.sessions.first
        XCTAssertEqual(reviewed?.endReason, .connectionLost)
        XCTAssertEqual(reviewed?.stopReviewDecision, .userInitiated)
        XCTAssertEqual(reviewed?.status, .completed)
        XCTAssertEqual(model.state.interruptedCount, 0)
    }

    /// 指定条件を持つ終了済みセッションを生成します。
    ///
    /// 責務: テスト入力を終了日時と終了理由が確定した1件のセッションへ変換します。
    /// - Parameters:
    ///   - startedAt: Unix秒で表す開始日時。
    ///   - duration: 終了までの秒数。
    ///   - reason: 終了理由。
    ///   - vehicle: 関連付ける車両情報。
    /// - Returns: 指定条件を保持する終了済みセッション。
    private func makeClosedSession(
        startedAt: TimeInterval,
        duration: TimeInterval,
        reason: ConnectionSessionEndReason,
        vehicle: ConnectionSessionVehicle
    ) -> ConnectionSession {
        let start = Date(timeIntervalSince1970: startedAt)
        var session = ConnectionSession(accountIdentifier: "account", startedAt: start, vehicle: vehicle)
        session.endedAt = start.addingTimeInterval(duration)
        session.endReason = reason
        return session
    }
}

/// 削除マーカー取得を明示再開まで停止する同期テスト実装です。
@MainActor
private final class PausingConnectionSessionTransferRepository: ConnectionSessionTransferRepository {
    /// 削除マーカー取得の呼出回数です。
    private(set) var deletionRequestCount = 0
    /// 停止中の削除マーカー取得を再開する継続です。
    private var deletionContinuation: CheckedContinuation<Set<ConnectionSessionID>, Never>?

    /// このテストではアップロードを固定Digestで受理します。
    ///
    /// 責務: テスト対象外の転送保存要求を副作用なしで満たします。
    /// - Parameters:
    ///   - package: 使用しない転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String {
        "digest"
    }

    /// このテストでは転送Payloadを返しません。
    ///
    /// 責務: テスト対象外のCloudKit取得要求へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空の転送配列。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] { [] }

    /// このテストではMac受領証公開を行いません。
    ///
    /// 責務: テスト対象外の受領証保存要求を副作用なしで満たします。
    /// - Parameters:
    ///   - receipt: 使用しないMac受領証。
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {}

    /// このテストではMac受領証を返しません。
    ///
    /// 責務: テスト対象外の受領証取得要求へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空の受領証配列。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// 削除マーカー取得をテストから再開されるまで停止します。
    ///
    /// 責務: 1件の削除マーカー取得要求を進行中同期として観測可能にします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 再開後の空セッションID集合。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> {
        deletionRequestCount += 1
        return await withCheckedContinuation { deletionContinuation = $0 }
    }

    /// このテストでは単一セッション削除を行いません。
    ///
    /// 責務: テスト対象外のCloudKit削除要求を副作用なしで満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// このテストではアカウント全削除を行いません。
    ///
    /// 責務: テスト対象外のCloudKit全削除要求を副作用なしで満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {}

    /// 最初の削除マーカー取得開始まで待機します。
    ///
    /// 責務: テスト実行を同期Taskが停止点へ到達した時点まで進めます。
    func waitForDeletionRequest() async {
        while deletionRequestCount == 0 { await Task.yield() }
    }

    /// 停止中の削除マーカー取得へ空集合を返して再開します。
    ///
    /// 責務: 保持中の1件の同期継続を空の削除結果で完了します。
    func resumeDeletionRequest() {
        deletionContinuation?.resume(returning: [])
        deletionContinuation = nil
    }
}

/// Rawログを保持しない同期モデルテスト実装です。
private struct EmptyConnectionSessionRawLogRepository: ConnectionSessionRawLogRepository {
    /// Raw応答追記を副作用なしで受理します。
    ///
    /// 責務: テスト対象外のRaw追記要求を満たします。
    /// - Parameters:
    ///   - observation: 使用しないRaw応答。
    ///   - sessionID: 使用しないセッションID。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws {}

    /// 空のセッションRawログを返します。
    ///
    /// 責務: 任意セッションIDを空のRawログ配列へ変換します。
    /// - Parameter sessionID: 使用しないセッションID。
    /// - Returns: 空配列。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] { [] }

    /// 空の車両別Rawログを返します。
    ///
    /// 責務: 任意車両スコープを空のRawログ配列へ変換します。
    /// - Parameters:
    ///   - vehicleID: 使用しない車両ID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func entries(for vehicleID: VehicleID, accountIdentifier: String) throws -> [VehicleConnectionSessionRawLogEntry] { [] }

    /// CloudKit保存済み更新を副作用なしで受理します。
    ///
    /// 責務: テスト対象外のManifest保存要求を満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - manifestDigest: 使用しないDigest。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {}

    /// CloudKit失敗更新を副作用なしで受理します。
    ///
    /// 責務: テスト対象外の失敗保存要求を満たします。
    /// - Parameter sessionID: 使用しないセッションID。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {}

    /// Mac受領証更新を副作用なしで受理します。
    ///
    /// 責務: テスト対象外の受領証保存要求を満たします。
    /// - Parameters:
    ///   - receipt: 使用しない受領証。
    ///   - sessionID: 使用しないセッションID。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {}

    /// 検証済み転送取込を副作用なしで受理します。
    ///
    /// 責務: テスト対象外の転送取込要求を満たします。
    /// - Parameter transfer: 使用しない転送Payload。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {}

    /// ローカルRaw除去を副作用なしで受理します。
    ///
    /// 責務: テスト対象外のRaw除去要求を満たします。
    /// - Parameter sessionID: 使用しないセッションID。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {}
}

/// セッション削除を行わない同期モデルテスト実装です。
private struct NoOpConnectionSessionErasureRepository: ConnectionSessionErasureRepository {
    /// ローカルセッション削除を副作用なしで受理します。
    ///
    /// 責務: テスト対象外の物理削除要求を満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) throws {}
}

/// 保存内容を更新可能な接続履歴テスト実装です。
private final class MutableConnectionSessionRepository: ConnectionSessionRepository {
    /// 現在保持するセッション一覧です。
    private var storedSessions: [ConnectionSession]

    /// 初期セッション一覧を固定して生成します。
    ///
    /// 責務: 1件の固定セッション配列を更新可能なテスト保存先へ変換します。
    /// - Parameter sessions: 初期状態として保持するセッション一覧。
    init(sessions: [ConnectionSession]) {
        storedSessions = sessions
    }

    /// 同じIDのセッションを現在内容で置き換えます。
    ///
    /// 責務: 1件のセッション保存要求をID単位のテスト状態更新へ変換します。
    /// - Parameter session: 保存する接続セッション。
    func save(_ session: ConnectionSession) throws {
        storedSessions.removeAll { $0.id == session.id }
        storedSessions.append(session)
    }

    /// 指定アカウントのセッションを新しい順で返します。
    ///
    /// 責務: 現在のテスト履歴を1件のアカウント識別子で絞り込みます。
    /// - Parameter accountIdentifier: 取得対象のアカウント識別子。
    /// - Returns: 開始日時が新しい順の該当セッション。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        storedSessions
            .filter { $0.accountIdentifier == accountIdentifier }
            .sorted { $0.startedAt > $1.startedAt }
    }
}

/// テスト用の固定接続履歴を返します。
private struct FixedConnectionSessionRepository: ConnectionSessionRepository {
    /// 取得要求へ返す固定セッション一覧です。
    let sessions: [ConnectionSession]

    /// この読込専用テスト実装では保存を行いません。
    ///
    /// 責務: 保存要求を副作用なしで受理します。
    /// - Parameter session: 使用しない接続セッション。
    func save(_ session: ConnectionSession) throws {}

    /// 固定セッションから指定アカウント分を返します。
    ///
    /// 責務: 固定履歴を1件のアカウント識別子で絞り込みます。
    /// - Parameter accountIdentifier: 取得対象のアカウント識別子。
    /// - Returns: 指定アカウントに属する固定履歴。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        sessions.filter { $0.accountIdentifier == accountIdentifier }
    }
}
