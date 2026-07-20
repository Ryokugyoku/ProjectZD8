import Foundation
import XCTest
@testable import ProjectZD8

/// セッション転送とMac取込受領証の端末役割別処理を検証します。
@MainActor
final class SynchronizeConnectionSessionsUseCaseTests: XCTestCase {
    /// 同じセッションの複数受領証ではCloudKitが返した最新1件だけを反映します。
    ///
    /// 責務: iPhoneが古いMac受領証で最新の取込証跡を上書きしないことを確認します。
    func testIPhoneAppliesOnlyNewestReceiptForEachSession() async throws {
        let sessionID = ConnectionSessionID()
        let newest = makeReceipt(deviceID: "new", importedAt: 200)
        let older = makeReceipt(deviceID: "old", importedAt: 100)
        let local = SynchronizationLocalRepository(sessions: [])
        let cloud = SynchronizationTransferRepository(
            transfers: [],
            receipts: [(sessionID, newest), (sessionID, older)]
        )
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            transferRepository: cloud,
            role: .iPhone
        )

        try await useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(local.markedReceipts.count, 1)
        XCTAssertEqual(local.markedReceipts.first?.0, sessionID)
        XCTAssertEqual(local.markedReceipts.first?.1, newest)
    }

    /// Macは検証済みPayloadをローカルへ取り込んでから同じManifestの受領証を公開します。
    ///
    /// 責務: Mac同期が車両付きセッション取込、ローカル証跡、CloudKit受領証の順で完了することを確認します。
    func testMacImportsTransferAndPublishesMatchingReceipt() async throws {
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
        let cloud = SynchronizationTransferRepository(transfers: [transfer], receipts: [])
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            transferRepository: cloud,
            role: .macOS,
            installationIdentity: LocalInstallationIdentity(id: "mac-installation", displayName: "Garage Mac"),
            now: { Date(timeIntervalSince1970: 120) }
        )

        try await useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(local.importedTransfers, [transfer])
        XCTAssertEqual(local.markedReceipts.first?.0, session.id)
        XCTAssertEqual(local.markedReceipts.first?.1.manifestDigest, "manifest")
        XCTAssertEqual(local.markedReceipts.first?.1.deviceID, "mac-installation")
        XCTAssertEqual(cloud.publishedReceipts.first?.0, session.id)
        XCTAssertEqual(cloud.publishedReceipts.first?.1, local.markedReceipts.first?.1)
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
private final class SynchronizationLocalRepository: ConnectionSessionRepository, ConnectionSessionRawLogRepository {
    /// 一覧取得で返すセッションです。
    private let storedSessions: [ConnectionSession]
    /// 取り込まれた検証済み転送です。
    private(set) var importedTransfers: [VerifiedConnectionSessionTransfer] = []
    /// 反映されたセッションIDとMac受領証です。
    private(set) var markedReceipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] = []

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

    /// このテストではCloudKit保存済み更新を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のManifest更新要求を満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - manifestDigest: 使用しないDigest。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {}

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

    /// このテストではローカル除去を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のローカル除去要求を満たします。
    /// - Parameter sessionID: 使用しないセッションID。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {}
}

/// 同期ユースケースのCloudKit操作をメモリ上で再現します。
@MainActor
private final class SynchronizationTransferRepository: ConnectionSessionTransferRepository {
    /// 取得で返す検証済み転送です。
    private let transfers: [VerifiedConnectionSessionTransfer]
    /// 取得で返すMac受領証です。
    private let receipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)]
    /// 公開されたMac受領証です。
    private(set) var publishedReceipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] = []

    /// 固定転送と受領証を保持します。
    ///
    /// 責務: CloudKit取得結果として返す同期データを初期化します。
    /// - Parameters:
    ///   - transfers: 取得で返す検証済み転送。
    ///   - receipts: 取得で返すMac受領証。
    init(
        transfers: [VerifiedConnectionSessionTransfer],
        receipts: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)]
    ) {
        self.transfers = transfers
        self.receipts = receipts
    }

    /// このテストでは固定Digestを返します。
    ///
    /// 責務: テスト対象外のCloudKit送信要求を満たします。
    /// - Parameters:
    ///   - package: 使用しない転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String {
        "uploaded"
    }

    /// 固定の検証済み転送を返します。
    ///
    /// 責務: Mac同期へ注入済み転送Payloadを供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に保持した検証済み転送。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] {
        transfers
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

    /// このテストではCloudKit全削除を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のアカウント運転データ削除要求を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {}
}
