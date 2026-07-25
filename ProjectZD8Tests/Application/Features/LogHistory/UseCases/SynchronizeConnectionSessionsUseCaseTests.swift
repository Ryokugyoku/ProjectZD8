import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// Raw非包含セッション概要とCloudKit Raw保管の端末間同期を検証します。
@MainActor
final class SynchronizeConnectionSessionsUseCaseTests: XCTestCase {
    /// CloudKit削除マーカーを送信判定より先にローカル物理削除へ反映します。
    ///
    /// 責務: 削除済みセッションが別端末から再アップロードされない同期順序を確認します。
    func testDeletionMarkerRemovesLocalSessionBeforeUpload() async throws {
        var session = ConnectionSession(accountIdentifier: "account")
        session.endedAt = Date()
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 1,
            localState: .available,
            cloudState: .pending,
            manifestDigest: nil,
            macImportReceipt: nil
        )
        let local = SynchronizationLocalRepository(sessions: [session])
        let cloud = SynchronizationTransferRepository(
            transfers: [],
            receipts: [],
            deletedIDs: [session.id]
        )
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(local.deletedSessionIDs, [session.id])
        XCTAssertTrue(cloud.uploadedSessionIDs.isEmpty)
    }

    /// 通常の履歴更新では送信待ちセッションをアップロードせず、個別要求で対象だけを送信します。
    ///
    /// 責務: 受信中心の更新と明示的な単一セッションアップロードが混在しないことを確認します。
    func testRefreshDoesNotUploadPendingSessionUntilExplicitRequest() async throws {
        var session = ConnectionSession(accountIdentifier: "account")
        session.endedAt = Date()
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 1,
            localState: .available,
            cloudState: .pending,
            manifestDigest: nil,
            macImportReceipt: nil
        )
        let local = SynchronizationLocalRepository(sessions: [session])
        let cloud = SynchronizationTransferRepository(transfers: [], receipts: [])
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account")
        XCTAssertTrue(cloud.uploadedSessionIDs.isEmpty)

        try await useCase.upload(sessionID: session.id, accountIdentifier: "account")
        XCTAssertEqual(cloud.uploadedSessionIDs, [session.id])
        XCTAssertEqual(try XCTUnwrap(local.sessions(for: "account").first).rawLogSummary.cloudState, .uploaded)
    }

    /// 同じセッションの複数受領証ではCloudKitが返した最新1件だけを反映します。
    ///
    /// 責務: iPhoneが古いMac受領証で最新の取込証跡を上書きしないことを確認します。
    func testIPhoneAppliesOnlyNewestReceiptForEachSession() async throws {
        let sessionID = ConnectionSessionID()
        let newest = makeReceipt(deviceID: "new", importedAt: 200)
        let older = makeReceipt(deviceID: "old", importedAt: 100)
        var session = ConnectionSession(id: sessionID, accountIdentifier: "account")
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 0,
            byteCount: 0,
            localState: .empty,
            cloudState: .uploaded,
            manifestDigest: "manifest",
            macImportReceipt: nil
        )
        let local = SynchronizationLocalRepository(sessions: [session])
        let cloud = SynchronizationTransferRepository(
            transfers: [],
            receipts: [(sessionID, newest), (sessionID, older)]
        )
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(local.markedReceipts.count, 1)
        XCTAssertEqual(local.markedReceipts.first?.0, sessionID)
        XCTAssertEqual(local.markedReceipts.first?.1, newest)
    }

    /// iPhoneはCloudKit上の検証済みセッションをローカル履歴へ取り込みます。
    ///
    /// 責務: Macなど別端末で保存されたセッションがiPhone側へ復元されることを確認します。
    func testIPhoneImportsMetadataWithoutDownloadingRawPayload() async throws {
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: ConnectionSessionVehicle(profile: VehicleProfile(vin: "ZD8VIN", name: "BRZ"))
        )
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "manifest"
        )
        let local = SynchronizationLocalRepository(sessions: [])
        let cloud = SynchronizationTransferRepository(
            transfers: [transfer],
            metadata: [ConnectionSessionCloudMetadata(session: session, manifestDigest: "manifest")],
            receipts: []
        )
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(local.importedMetadata.map(\.session.id), [session.id])
        XCTAssertTrue(local.importedTransfers.isEmpty)
        XCTAssertTrue(local.markedReceipts.isEmpty)
        XCTAssertTrue(cloud.publishedReceipts.isEmpty)
    }

    /// Raw応答がないMacセッションも履歴としてCloudKitへ保存しiPhoneへ取り込みます。
    ///
    /// 責務: macOSで終了したメタデータのみのセッションがiPhone履歴へ届く双方向経路を確認します。
    func testMacMetadataOnlySessionUploadsAndIPhoneImports() async throws {
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: ConnectionSessionVehicle(profile: VehicleProfile(vin: "ZD8VIN", name: "BRZ"))
        )
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        let macLocal = SynchronizationLocalRepository(sessions: [session])
        let iPhoneLocal = SynchronizationLocalRepository(sessions: [])
        let cloud = SynchronizationTransferRepository(transfers: [], receipts: [])
        let macUseCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: macLocal,
            rawLogRepository: macLocal,
            sessionErasureRepository: macLocal,
            transferRepository: cloud,
            role: .macOS
        )
        let iPhoneUseCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: iPhoneLocal,
            rawLogRepository: iPhoneLocal,
            sessionErasureRepository: iPhoneLocal,
            transferRepository: cloud,
            role: .iPhone
        )

        try await macUseCase.execute(accountIdentifier: "account", uploadsPendingSessions: true)
        try await iPhoneUseCase.execute(accountIdentifier: "account")

        XCTAssertEqual(cloud.uploadedSessionIDs, [session.id])
        XCTAssertEqual(iPhoneLocal.importedMetadata.map(\.session.id), [session.id])
        XCTAssertTrue(iPhoneLocal.importedTransfers.isEmpty)
    }

    /// ローカルが送信済みでもCloudKitレコードが欠けていれば既存セッションを再公開します。
    ///
    /// 責務: 過去の送信済み状態だけが残ったMacセッションをCloudKitへ自己修復することを確認します。
    func testUploadedLocalSessionIsReuploadedWhenRemoteTransferIsMissing() async throws {
        var session = ConnectionSession(accountIdentifier: "account")
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 0,
            byteCount: 0,
            localState: .empty,
            cloudState: .uploaded,
            manifestDigest: "missing-remote-manifest",
            macImportReceipt: nil
        )
        let local = SynchronizationLocalRepository(sessions: [session])
        let cloud = SynchronizationTransferRepository(transfers: [], receipts: [])
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account", uploadsPendingSessions: true)

        XCTAssertEqual(cloud.uploadedSessionIDs, [session.id])
        XCTAssertEqual(local.importedMetadata.map(\.session.id), [session.id])
        let transferredSummary = try XCTUnwrap(local.importedMetadata.first?.session.rawLogSummary)
        XCTAssertEqual(transferredSummary.cloudState, .uploaded)
        XCTAssertEqual(transferredSummary.manifestDigest, "uploaded")
        XCTAssertNil(transferredSummary.macImportReceipt)
    }

    /// CloudKitに同じManifestが実在する送信済みセッションは再公開しません。
    ///
    /// 責務: 既存セッション救済が正常なCloudKitレコードを不要に上書きしないことを確認します。
    func testUploadedLocalSessionIsNotReuploadedWhenRemoteManifestMatches() async throws {
        var session = ConnectionSession(accountIdentifier: "account")
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 0,
            byteCount: 0,
            localState: .empty,
            cloudState: .uploaded,
            manifestDigest: "remote-manifest",
            macImportReceipt: nil
        )
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "remote-manifest"
        )
        let local = SynchronizationLocalRepository(sessions: [session])
        let cloud = SynchronizationTransferRepository(
            transfers: [transfer],
            metadata: [ConnectionSessionCloudMetadata(session: session, manifestDigest: "remote-manifest")],
            receipts: []
        )
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account", uploadsPendingSessions: true)

        XCTAssertTrue(cloud.uploadedSessionIDs.isEmpty)
        XCTAssertEqual(local.importedMetadata.map(\.session.id), [session.id])
        XCTAssertTrue(local.importedTransfers.isEmpty)
    }

    /// 失敗状態のローカルセッションは同じ旧Manifestがリモートに残っていても再公開します。
    ///
    /// 責務: 保存後に内容が進んだセッションが古いCloudKit転送を置換し、自身の旧Payloadを再取込しないことを確認します。
    func testFailedLocalSessionReplacesStaleRemoteTransferBeforeImport() async throws {
        var localSession = ConnectionSession(accountIdentifier: "account")
        localSession.endedAt = Date(timeIntervalSince1970: 120)
        localSession.endReason = .userDisconnected
        localSession.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 0,
            byteCount: 0,
            localState: .empty,
            cloudState: .failed,
            manifestDigest: "stale-manifest",
            macImportReceipt: nil
        )
        var staleRemoteSession = localSession
        staleRemoteSession.endedAt = Date(timeIntervalSince1970: 110)
        let staleTransfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: staleRemoteSession, entries: []),
            manifestDigest: "stale-manifest"
        )
        let local = SynchronizationLocalRepository(sessions: [localSession])
        let cloud = SynchronizationTransferRepository(
            transfers: [staleTransfer],
            metadata: [ConnectionSessionCloudMetadata(session: staleRemoteSession, manifestDigest: "stale-manifest")],
            receipts: []
        )
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account", uploadsPendingSessions: true)

        XCTAssertEqual(cloud.uploadedSessionIDs, [localSession.id])
        XCTAssertEqual(local.importedMetadata.count, 1)
        XCTAssertEqual(local.importedMetadata.first?.manifestDigest, "uploaded")
        XCTAssertEqual(local.importedMetadata.first?.session.endedAt, localSession.endedAt)
    }

    /// Macは検証済みPayloadをローカルへ取り込んでから同じManifestの受領証を公開します。
    ///
    /// 責務: Mac同期が車両付きセッション取込、ローカル証跡、CloudKit受領証の順で完了することを確認します。
    func testMacImportsMetadataWithoutDownloadingRawOrPublishingReceipt() async throws {
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: ConnectionSessionVehicle(profile: VehicleProfile(vin: "ZD8VIN", name: "BRZ"))
        )
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "manifest"
        )
        let local = SynchronizationLocalRepository(sessions: [])
        let cloud = SynchronizationTransferRepository(
            transfers: [transfer],
            metadata: [ConnectionSessionCloudMetadata(session: session, manifestDigest: "manifest")],
            receipts: []
        )
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .macOS
        )

        try await useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(local.importedMetadata.map(\.session.id), [session.id])
        XCTAssertTrue(local.importedTransfers.isEmpty)
        XCTAssertTrue(local.markedReceipts.isEmpty)
        XCTAssertTrue(cloud.publishedReceipts.isEmpty)
    }

    /// iPhoneとMacの概要同期で車両、取得端末、CloudKit保管状態を維持します。
    ///
    /// 責務: 2つの実GRDB保存先を跨ぐ同期がRawを自動取得せず履歴カード情報を共有することを確認します。
    func testRoundTripBetweenIPhoneAndMacPreservesSharedArchiveMetadata() async throws {
        let iPhone = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let mac = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let cloud = SynchronizationTransferRepository(transfers: [], receipts: [])
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        let sourceDevice = ConnectionSessionAcquisitionDevice(platform: .iPhone, name: "iPhone 17 Pro")
        var session = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100),
            vehicle: vehicle,
            acquisitionDevice: sourceDevice
        )
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        try iPhone.save(session)
        let iPhoneSync = SynchronizeConnectionSessionsUseCase(
            sessionRepository: iPhone,
            rawLogRepository: iPhone,
            sessionErasureRepository: iPhone,
            transferRepository: cloud,
            role: .iPhone
        )
        let macSync = SynchronizeConnectionSessionsUseCase(
            sessionRepository: mac,
            rawLogRepository: mac,
            sessionErasureRepository: mac,
            transferRepository: cloud,
            role: .macOS
        )

        try await iPhoneSync.execute(accountIdentifier: "account", uploadsPendingSessions: true)
        try await macSync.execute(accountIdentifier: "account")
        try await iPhoneSync.execute(accountIdentifier: "account")

        let iPhoneResult = try XCTUnwrap(iPhone.sessions(for: "account").first)
        let macResult = try XCTUnwrap(mac.sessions(for: "account").first)
        XCTAssertEqual(macResult.vehicle, vehicle)
        XCTAssertEqual(macResult.acquisitionDevice, sourceDevice)
        XCTAssertEqual(macResult.rawLogSummary.cloudState, .uploaded)
        XCTAssertEqual(macResult.rawLogSummary.localState, .empty)
        XCTAssertEqual(iPhoneResult.rawLogSummary.cloudState, .uploaded)
        XCTAssertNil(iPhoneResult.rawLogSummary.macImportReceipt)
    }

    /// 指定情報を持つMac取込受領証を生成します。
    ///
    /// 責務: iPhone受領証テストへ同一Manifestの時系列データを供給します。
    /// - Parameters:
    ///   - deviceID: 取込元Mac識別子。
    ///   - importedAt: 取込日時のUNIX秒。
    /// - Returns: `manifest` に対応するMac受領証。
    private func makeReceipt(deviceID: String, importedAt: TimeInterval) -> ConnectionSessionMacImportReceipt {
        ConnectionSessionMacImportReceipt(
            deviceID: deviceID,
            deviceName: deviceID,
            importedAt: Date(timeIntervalSince1970: importedAt),
            manifestDigest: "manifest"
        )
    }
}

/// 同期ユースケースのローカル保存操作を記録します。
private final class SynchronizationLocalRepository: ConnectionSessionRepository, ConnectionSessionRawLogRepository, ConnectionSessionErasureRepository {
    /// 一覧取得で返すセッションです。
    private var storedSessions: [ConnectionSession]
    /// 取り込まれた検証済み転送です。
    private(set) var importedTransfers: [VerifiedConnectionSessionTransfer] = []
    /// 取り込まれたRaw非包含セッション概要です。
    private(set) var importedMetadata: [ConnectionSessionCloudMetadata] = []
    /// 反映されたセッションIDとMac受領証です。
    private(set) var markedReceipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] = []
    /// 物理削除された接続セッションIDです。
    private(set) var deletedSessionIDs: [ConnectionSessionID] = []

    /// 固定セッション一覧を保持します。
    ///
    /// 責務: 同期対象として返すローカル履歴を初期化します。
    /// - Parameter sessions: 一覧取得で返すセッション。
    init(sessions: [ConnectionSession]) { storedSessions = sessions }

    /// このテストではセッション保存を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のセッション保存要求を満たします。
    /// - Parameter session: 使用しないセッション。
    func save(_ session: ConnectionSession) throws {}

    /// 固定セッション一覧を返します。
    ///
    /// 責務: 同期ユースケースへ注入済みローカル履歴を供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に保持したセッション一覧。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] { storedSessions }

    /// このテストではRaw応答追記を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のRaw応答追記要求を満たします。
    /// - Parameters:
    ///   - observation: 使用しないRaw応答。
    ///   - sessionID: 使用しないセッションID。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws {}

    /// このテストでは空のRawログを返します。
    ///
    /// 責務: 送信対象外テストへ空のRawログを供給します。
    /// - Parameter sessionID: 使用しないセッションID。
    /// - Returns: 空配列。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] { [] }

    /// このテストでは空の車両別Rawログを返します。
    ///
    /// 責務: テスト対象外の車両別Rawログ照会要求を満たします。
    /// - Parameters:
    ///   - vehicleID: 使用しない登録車両ID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func entries(
        for vehicleID: VehicleID,
        accountIdentifier: String
    ) throws -> [VehicleConnectionSessionRawLogEntry] { [] }

    /// CloudKit保存済みManifestをテスト用セッションへ反映します。
    ///
    /// 責務: 1件のアップロード結果を後続の概要公開で参照できる状態へ更新します。
    /// - Parameters:
    ///   - sessionID: 更新するセッションID。
    ///   - manifestDigest: 保存済みRaw PayloadのManifest。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {
        guard let index = storedSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        storedSessions[index].rawLogSummary.cloudState = .uploaded
        storedSessions[index].rawLogSummary.manifestDigest = manifestDigest
    }

    /// このテストではCloudKit失敗更新を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外の転送失敗要求を満たします。
    /// - Parameter sessionID: 使用しないセッションID。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {}

    /// Mac受領証と対象セッションを記録します。
    ///
    /// 責務: 同期ユースケースが反映したMac受領証を検査可能にします。
    /// - Parameters:
    ///   - receipt: 反映されたMac受領証。
    ///   - sessionID: 対象セッションID。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {
        markedReceipts.append((sessionID, receipt))
    }

    /// 検証済み転送を記録します。
    ///
    /// 責務: Mac同期がローカルへ渡した転送Payloadを検査可能にします。
    /// - Parameter transfer: 取り込まれた転送Payload。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {
        importedTransfers.append(transfer)
    }

    /// セッション概要をRaw Payloadとは別に記録します。
    ///
    /// 責務: 同期ユースケースが取り込んだ軽量概要を検査可能にします。
    /// - Parameter metadata: 取り込まれたセッション概要。
    func importCloudMetadata(_ metadata: ConnectionSessionCloudMetadata) throws {
        importedMetadata.append(metadata)
    }

    /// このテストではローカル除去を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のローカル除去要求を満たします。
    /// - Parameter sessionID: 使用しないセッションID。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {}

    /// 削除マーカーに対応するセッションIDを記録します。
    ///
    /// 責務: 1件のローカル物理削除要求を検査可能な履歴へ追加します。
    /// - Parameters:
    ///   - sessionID: 物理削除するセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) throws {
        deletedSessionIDs.append(sessionID)
        storedSessions.removeAll { $0.id == sessionID && $0.accountIdentifier == accountIdentifier }
    }
}

/// 同期ユースケースのCloudKit操作をメモリ上で再現します。
@MainActor
private final class SynchronizationTransferRepository: ConnectionSessionTransferRepository {
    /// 取得で返す検証済み転送です。
    private var transfers: [VerifiedConnectionSessionTransfer]
    /// 取得で返すRaw非包含セッション概要です。
    private var metadata: [ConnectionSessionCloudMetadata]
    /// 取得で返すMac受領証です。
    private var receipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)]
    /// 取得で返す削除済みセッションIDです。
    private let deletedIDs: Set<ConnectionSessionID>
    /// 公開されたMac受領証です。
    private(set) var publishedReceipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] = []
    /// CloudKitへ送信された接続セッションIDです。
    private(set) var uploadedSessionIDs: [ConnectionSessionID] = []

    /// 固定転送と受領証を保持します。
    ///
    /// 責務: CloudKit取得結果として返す同期データを初期化します。
    /// - Parameters:
    ///   - transfers: 取得で返す検証済み転送。
    ///   - metadata: 取得で返すRaw非包含セッション概要。
    ///   - receipts: 取得で返すMac受領証。
    init(
        transfers: [VerifiedConnectionSessionTransfer],
        metadata: [ConnectionSessionCloudMetadata] = [],
        receipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)],
        deletedIDs: Set<ConnectionSessionID> = []
    ) {
        self.transfers = transfers
        self.metadata = metadata
        self.receipts = receipts
        self.deletedIDs = deletedIDs
    }

    /// 送信Payloadを後続端末が取得できる転送として記録します。
    ///
    /// 責務: 1件のCloudKit送信要求を検証済み転送と送信履歴へ変換します。
    /// - Parameters:
    ///   - package: 後続の取得へ保存する転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String {
        uploadedSessionIDs.append(package.sessionID)
        transfers.removeAll { $0.package.sessionID == package.sessionID }
        transfers.append(VerifiedConnectionSessionTransfer(package: package, manifestDigest: "uploaded"))
        return "uploaded"
    }

    /// 固定の検証済み転送を返します。
    ///
    /// 責務: Mac同期へ注入済み転送Payloadを供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に保持した検証済み転送。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] {
        transfers
    }

    /// 公開されたRaw非包含概要を後続端末が取得できる状態へ保存します。
    ///
    /// 責務: 1件の概要公開要求をセッションID単位のメモリ上Metadataレコードへ変換します。
    /// - Parameters:
    ///   - item: 保存するRaw非包含セッション概要。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMetadata(
        _ item: ConnectionSessionCloudMetadata,
        for accountIdentifier: String
    ) async throws {
        metadata.removeAll { $0.session.id == item.session.id }
        metadata.append(item)
    }

    /// メモリ上に保存したRaw非包含概要を返します。
    ///
    /// 責務: 概要取得要求を現在保存中のMetadata配列へ変換します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 現在保存中のRaw非包含概要。
    func downloadMetadata(for accountIdentifier: String) async throws -> [ConnectionSessionCloudMetadata] {
        metadata
    }

    /// 公開されたMac受領証を記録します。
    ///
    /// 責務: Mac同期がCloudKitへ公開した受領証を検査可能にします。
    /// - Parameters:
    ///   - receipt: 公開されたMac受領証。
    ///   - sessionID: 対象セッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {
        publishedReceipts.append((sessionID, receipt))
        receipts.removeAll { $0.0 == sessionID && $0.1.deviceID == receipt.deviceID }
        receipts.append((sessionID, receipt))
        receipts.sort { $0.1.importedAt > $1.1.importedAt }
    }

    /// 固定のMac受領証を返します。
    ///
    /// 責務: iPhone同期へ注入済み受領証順を供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に保持したMac受領証。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] {
        receipts
    }

    /// 固定の削除済みセッションIDを返します。
    ///
    /// 責務: 同期ユースケースへ注入済み削除マーカーを供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に保持した削除済みセッションID集合。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> {
        deletedIDs
    }

    /// この同期テストでは単体のCloudKit削除を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のセッション削除要求を副作用なしで満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// このテストではCloudKit全削除を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のアカウント運転データ削除要求を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {}
}
