import XCTest
@testable import ProjectZD8

/// 接続セッションの同期が、アップロード・公開の直前に削除済みの印を確認することを仕様から検証します。
///
/// 仕様: execute のアップロードと概要公開の前、単発の `upload(sessionID:)` の前に確認する。
/// 印がある、または確認に失敗した時は、アップロードも保存(公開)も呼ばれない。
@MainActor
final class SynchronizeConnectionSessionsUseCaseDeletionMarkerTests: XCTestCase {
    /// 確認の失敗を表す検証用エラーです。
    private struct CheckFailure: Error, Equatable {}

    /// 印がある時、execute のアップロードが呼ばれず、`accountDeleted` で止まることを検証します。
    ///
    /// 責務: 送信待ちセッションがあっても、アップロードもローカル状態の更新も起きないことを確認します。
    func testExecuteWithMarkerDoesNotUploadPendingSession() async throws {
        let fixture = makeFixture(sessions: [pendingSession()])
        fixture.marker.deletedAccounts = ["account"]

        await assertThrowsAccountDeleted { try await fixture.useCase.execute(accountIdentifier: "account", uploadsPendingSessions: true) }

        XCTAssertTrue(fixture.cloud.uploadedSessionIDs.isEmpty)
        XCTAssertEqual(try XCTUnwrap(fixture.local.sessions(for: "account").first).rawLogSummary.cloudState, .pending)
        XCTAssertEqual(fixture.notified, ["account"])
    }

    /// 印がなければ、同じ条件でアップロードされることを検証します(上の検証が空振りでないことの対照)。
    ///
    /// 責務: 印なしでは送信待ちセッションがアップロードされることを確認します。
    func testExecuteWithoutMarkerUploadsPendingSession() async throws {
        let session = pendingSession()
        let fixture = makeFixture(sessions: [session])

        try await fixture.useCase.execute(accountIdentifier: "account", uploadsPendingSessions: true)

        XCTAssertEqual(fixture.cloud.uploadedSessionIDs, [session.id])
        XCTAssertTrue(fixture.notified.isEmpty)
    }

    /// 印がある時、アップロードしない同期でも概要の公開が呼ばれないことを検証します。
    ///
    /// 責務: 遠隔に実体だけある送信済みセッションの概要が、印がある時は公開されないことを確認します。
    func testExecuteWithMarkerDoesNotPublishLocalMetadata() async throws {
        let session = uploadedSessionWithRemoteTransferOnly()
        let fixture = makeFixture(sessions: [session.local], transfers: [session.transfer])
        fixture.marker.deletedAccounts = ["account"]

        await assertThrowsAccountDeleted { try await fixture.useCase.execute(accountIdentifier: "account") }

        let published = try await fixture.cloud.downloadMetadata(for: "account")
        XCTAssertTrue(published.isEmpty)
    }

    /// 印がなければ、同じ条件で概要が公開されることを検証します(上の検証が空振りでないことの対照)。
    ///
    /// 責務: 印なしでは遠隔に実体だけある送信済みセッションの概要が公開されることを確認します。
    func testExecuteWithoutMarkerPublishesLocalMetadata() async throws {
        let session = uploadedSessionWithRemoteTransferOnly()
        let fixture = makeFixture(sessions: [session.local], transfers: [session.transfer])

        try await fixture.useCase.execute(accountIdentifier: "account")

        let published = try await fixture.cloud.downloadMetadata(for: "account")
        XCTAssertEqual(published.map(\.session.id), [session.local.id])
    }

    /// 印の確認に失敗した時、execute はそのエラーで止まり、アップロードも公開もしないことを検証します。
    ///
    /// 責務: 確認できない場合を「印なし」として進めないことを確認します。
    func testExecuteWhenCheckFailsDoesNotUploadNorPublish() async throws {
        let fixture = makeFixture(sessions: [pendingSession()])
        fixture.marker.isDeletedError = CheckFailure()

        do {
            try await fixture.useCase.execute(accountIdentifier: "account", uploadsPendingSessions: true)
            XCTFail("印の確認に失敗したのに同期が成功しました。")
        } catch {
            XCTAssertEqual(error as? CheckFailure, CheckFailure())
        }

        XCTAssertTrue(fixture.cloud.uploadedSessionIDs.isEmpty)
        let published = try await fixture.cloud.downloadMetadata(for: "account")
        XCTAssertTrue(published.isEmpty)
    }

    /// 印がある時、単発の `upload(sessionID:)` がアップロードしないことを検証します。
    ///
    /// 責務: 個別のアップロード要求でも、印があれば送信されないことを確認します。
    func testSingleUploadWithMarkerDoesNotUpload() async throws {
        let session = pendingSession()
        let fixture = makeFixture(sessions: [session])
        fixture.marker.deletedAccounts = ["account"]

        await assertThrowsAccountDeleted { try await fixture.useCase.upload(sessionID: session.id, accountIdentifier: "account") }

        XCTAssertTrue(fixture.cloud.uploadedSessionIDs.isEmpty)
        XCTAssertEqual(fixture.notified, ["account"])
    }

    /// 印の確認に失敗した時、単発のアップロードがそのエラーで止まることを検証します。
    ///
    /// 責務: 確認失敗時に単発のアップロードが呼ばれないことを確認します。
    func testSingleUploadWhenCheckFailsDoesNotUpload() async throws {
        let session = pendingSession()
        let fixture = makeFixture(sessions: [session])
        fixture.marker.isDeletedError = CheckFailure()

        do {
            try await fixture.useCase.upload(sessionID: session.id, accountIdentifier: "account")
            XCTFail("印の確認に失敗したのにアップロードが成功しました。")
        } catch {
            XCTAssertEqual(error as? CheckFailure, CheckFailure())
        }

        XCTAssertTrue(fixture.cloud.uploadedSessionIDs.isEmpty)
    }

    /// 印がなければ、単発のアップロードが実行されることを検証します(対照)。
    ///
    /// 責務: 印なしで単発のアップロードが送信されることを確認します。
    func testSingleUploadWithoutMarkerUploads() async throws {
        let session = pendingSession()
        let fixture = makeFixture(sessions: [session])

        try await fixture.useCase.upload(sessionID: session.id, accountIdentifier: "account")

        XCTAssertEqual(fixture.cloud.uploadedSessionIDs, [session.id])
    }

    /// 検証対象と各Fakeの組です。
    private final class Fixture {
        /// 検証対象のユースケースです。
        let useCase: SynchronizeConnectionSessionsUseCase
        /// 端末内の保存先Fakeです。
        let local: SynchronizationLocalRepository
        /// CloudKitのFakeです。
        let cloud: SynchronizationTransferRepository
        /// 印のFakeです。
        let marker: AccountDeletionMarkerPortFake
        /// 印を検出して通知されたアカウント識別子です。
        var notified: [String] = []

        /// 部品を束ねます。
        ///
        /// 責務: 検証に使う各部品を1件の組へ保持します。
        init(
            useCase: SynchronizeConnectionSessionsUseCase,
            local: SynchronizationLocalRepository,
            cloud: SynchronizationTransferRepository,
            marker: AccountDeletionMarkerPortFake
        ) {
            self.useCase = useCase
            self.local = local
            self.cloud = cloud
            self.marker = marker
        }
    }

    /// 印の確認を結び付けた同期ユースケースを組み立てます。
    ///
    /// 責務: 印のFakeを `AccountDeletionMarkerGate` 経由で確認処理として注入します。
    /// - Parameters:
    ///   - sessions: 端末内のセッション。
    ///   - transfers: CloudKitにある転送実体。
    /// - Returns: ユースケースとFakeの組。
    private func makeFixture(
        sessions: [ConnectionSession],
        transfers: [VerifiedConnectionSessionTransfer] = []
    ) -> Fixture {
        let local = SynchronizationLocalRepository(sessions: sessions)
        let cloud = SynchronizationTransferRepository(transfers: transfers, receipts: [])
        let marker = AccountDeletionMarkerPortFake()
        let gate = AccountDeletionMarkerGate(marker: marker)
        let useCase = SynchronizeConnectionSessionsUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            sessionErasureRepository: local,
            transferRepository: cloud,
            role: .iPhone,
            accountDeletionCheck: { try await gate.ensureAccountNotDeleted(for: $0) }
        )
        let fixture = Fixture(useCase: useCase, local: local, cloud: cloud, marker: marker)
        gate.onAccountDeleted = { [unowned fixture] in fixture.notified.append($0) }
        return fixture
    }

    /// 終了済みでアップロード待ちのセッションを作ります。
    ///
    /// 責務: 通常のアップロード対象になるセッションを返します。
    /// - Returns: アップロード待ちのセッション。
    private func pendingSession() -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: "account")
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1, byteCount: 1, localState: .available, cloudState: .pending,
            manifestDigest: nil, macImportReceipt: nil
        )
        return session
    }

    /// 遠隔に実体だけがあり、概要が未公開の送信済みセッションを作ります。
    ///
    /// 責務: アップロードを伴わず概要の公開だけが起きる条件を作ります。
    /// - Returns: 端末内のセッションと遠隔の転送実体。
    private func uploadedSessionWithRemoteTransferOnly() -> (local: ConnectionSession, transfer: VerifiedConnectionSessionTransfer) {
        var session = ConnectionSession(accountIdentifier: "account")
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 0, byteCount: 0, localState: .empty, cloudState: .uploaded,
            manifestDigest: "remote-manifest", macImportReceipt: nil
        )
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "remote-manifest"
        )
        return (session, transfer)
    }

    /// 操作が `accountDeleted` で失敗することを確認します。
    ///
    /// 責務: 印による停止のエラー種別の検証を共通化します。
    /// - Parameter operation: 実行する操作。
    private func assertThrowsAccountDeleted(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("印があるのに処理が成功しました。")
        } catch {
            XCTAssertEqual(error as? AccountDeletionMarkerError, .accountDeleted)
        }
    }
}
