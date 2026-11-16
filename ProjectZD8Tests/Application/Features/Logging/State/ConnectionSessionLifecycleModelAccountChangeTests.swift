import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// アカウントが変わった(サインアウトした)時点で開いていた接続セッションが、後から届く取得の終了通知の理由・時刻で閉じられ、
/// 終了通知が来ないまま次にアカウントが変わった時は最初に変わった時刻の `accountSignedOut` で閉じられることを検証します。
///
/// 仕様: U8 R1(取得記録・終了通知・接続セッションの3つの終了理由を `accountSignedOut` で揃える)。
@MainActor
final class ConnectionSessionLifecycleModelAccountChangeTests: XCTestCase {
    /// 実時刻の手動 clock です。
    private let dates = ManualDateClock(Date(timeIntervalSince1970: 100))
    /// 終了を保存できたセッションの通知先へ渡されたセッションです。
    private var persistedEnds: [ConnectionSession] = []

    /// サインアウトの後に届いた終了通知で、開いていたセッションがその理由と時刻で閉じられます。
    ///
    /// 責務: サインアウト後の `endRequested(.accountSignedOut, endedAt:)` で、保存されたセッションの終了理由・終了時刻が通知のとおりで、
    /// 終了の保存の通知が1回であることを確認します。
    func testEndAfterSignOutClosesHeldSessionWithNotifiedReasonAndTime() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let model = makeModel(repository: repository)
        let sessionID = try startSession(model, account: "account")
        dates.set(Date(timeIntervalSince1970: 200))
        model.send(.accountIdentifierChanged(nil))
        dates.set(Date(timeIntervalSince1970: 300))

        model.send(.endRequested(.accountSignedOut, endedAt: Date(timeIntervalSince1970: 250)))

        let stored = try XCTUnwrap(try repository.sessions(for: "account").first { $0.id == sessionID })
        XCTAssertEqual(stored.endReason, .accountSignedOut)
        XCTAssertEqual(stored.endedAt, Date(timeIntervalSince1970: 250))
        XCTAssertEqual(persistedEnds.map(\.id), [sessionID])
        XCTAssertNil(model.activeSession)
    }

    /// 終了通知が時刻を持たなければ、通知を処理した時刻で閉じます。
    ///
    /// 責務: サインアウト後の `endRequested(.accountSignedOut)` で、終了時刻が処理した時刻(300秒)になることを確認します。
    func testEndAfterSignOutWithoutTimeUsesProcessedTime() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let model = makeModel(repository: repository)
        let sessionID = try startSession(model, account: "account")
        dates.set(Date(timeIntervalSince1970: 200))
        model.send(.accountIdentifierChanged(nil))
        dates.set(Date(timeIntervalSince1970: 300))

        model.send(.endRequested(.accountSignedOut))

        let stored = try XCTUnwrap(try repository.sessions(for: "account").first { $0.id == sessionID })
        XCTAssertEqual(stored.endReason, .accountSignedOut)
        XCTAssertEqual(stored.endedAt, Date(timeIntervalSince1970: 300))
    }

    /// 終了通知が来ないまま別のアカウントでサインインしたら、前のセッションは最初にアカウントが変わった時刻の `accountSignedOut` で閉じ、
    /// 新しいアカウントのセッションへ混ざりません。
    ///
    /// 責務: 200秒のサインアウト・400秒の別アカウントのサインインで、前のセッションが200秒・`accountSignedOut` で閉じ、
    /// 新しいアカウントの履歴に含まれず、新しいアカウントで始めたセッションの終了が前のセッションへ及ばないことを確認します。
    func testAccountChangeWithoutEndNotificationClosesAtFirstChangeTime() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let model = makeModel(repository: repository)
        let previousID = try startSession(model, account: "account")
        dates.set(Date(timeIntervalSince1970: 200))
        model.send(.accountIdentifierChanged(nil))
        dates.set(Date(timeIntervalSince1970: 400))

        model.send(.accountIdentifierChanged("other"))

        let previous = try XCTUnwrap(try repository.sessions(for: "account").first { $0.id == previousID })
        XCTAssertEqual(previous.endReason, .accountSignedOut)
        XCTAssertEqual(previous.endedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(try repository.sessions(for: "other"), [])
        XCTAssertNil(model.activeSession, "前のアカウントのセッションを再開しない")

        let newID = try startSession(model, account: nil)
        dates.set(Date(timeIntervalSince1970: 500))
        model.send(.endRequested(.userDisconnected))
        XCTAssertEqual(try repository.sessions(for: "other").map(\.id), [newID])
        XCTAssertEqual(try repository.sessions(for: "other").first?.endReason, .userDisconnected)
        XCTAssertEqual(try repository.sessions(for: "account").first { $0.id == previousID }?.endReason, .accountSignedOut, "前のセッションは変わらない")
        XCTAssertEqual(persistedEnds.map(\.id), [previousID, newID])
    }

    /// 前のアカウントへサインインし直しても、サインアウトで閉じたセッションは続行も異常終了の回収もされません。
    ///
    /// 責務: サインアウト後の終了通知で閉じた後に同じアカウントを有効化しても、終了理由・時刻が変わらず、開いたセッションが無いことを確認します。
    func testSignInAgainDoesNotResumeSessionClosedBySignOut() throws {
        let repository = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        let model = makeModel(repository: repository)
        let sessionID = try startSession(model, account: "account")
        dates.set(Date(timeIntervalSince1970: 200))
        model.send(.accountIdentifierChanged(nil))
        model.send(.endRequested(.accountSignedOut))
        dates.set(Date(timeIntervalSince1970: 900))

        model.send(.accountIdentifierChanged("account"))

        let stored = try XCTUnwrap(try repository.sessions(for: "account").first { $0.id == sessionID })
        XCTAssertEqual(stored.endReason, .accountSignedOut)
        XCTAssertEqual(stored.endedAt, Date(timeIntervalSince1970: 200))
        XCTAssertNil(model.activeSession)
        XCTAssertEqual(persistedEnds.map(\.id), [sessionID])
    }

    /// セッションが開いていない時のサインアウトと終了通知では、何も保存しません。
    ///
    /// 責務: 開始していないアカウントのサインアウト・終了通知・別アカウントの有効化で、保存も終了の通知も無いことを確認します。
    func testSignOutWithoutOpenSessionDoesNothing() throws {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = makeModel(repository: repository)
        model.send(.accountIdentifierChanged("account"))

        model.send(.accountIdentifierChanged(nil))
        model.send(.endRequested(.accountSignedOut))
        model.send(.accountIdentifierChanged("other"))

        XCTAssertEqual(repository.saved, [])
        XCTAssertEqual(persistedEnds, [])
    }

    /// サインアウト後の終了の保存に失敗したら、セッションを待つ側に残し、次の終了通知で閉じます。
    ///
    /// 責務: 1回目の保存失敗で終了の通知が無く、2回目の終了通知で `accountSignedOut` の保存と通知が1回ずつ行われることを確認します。
    func testSaveFailureAfterSignOutKeepsSessionAwaitingEnd() throws {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = makeModel(repository: repository)
        let sessionID = try startSession(model, account: "account")
        model.send(.accountIdentifierChanged(nil))
        repository.failsSave = true

        model.send(.endRequested(.accountSignedOut))
        XCTAssertEqual(persistedEnds, [])

        repository.failsSave = false
        model.send(.endRequested(.accountSignedOut))
        XCTAssertEqual(persistedEnds.map(\.id), [sessionID])
        XCTAssertEqual(persistedEnds.first?.endReason, .accountSignedOut)
    }

    /// 指定アカウントを有効化してセッションを開始します。
    ///
    /// 責務: アカウントの有効化(`nil` なら有効化しない)と開始要求を送り、開いたセッションのIDを返します。
    /// - Parameters:
    ///   - model: 検証対象。
    ///   - account: 有効化するアカウント識別子。`nil` なら現在のアカウントのまま。
    /// - Returns: 開いたセッションのID。
    private func startSession(_ model: ConnectionSessionLifecycleModel, account: String?) throws -> ConnectionSessionID {
        if let account { model.send(.accountIdentifierChanged(account)) }
        model.send(.startRequested)
        return try XCTUnwrap(model.activeSession?.id)
    }

    /// 手動 clock と終了の保存の記録へ結び付けたモデルを作ります。
    ///
    /// 責務: 指定の保存先で、時刻を手動 clock から取り、終了の保存の通知をこのテストへ記録するモデルを返します。
    /// - Parameter repository: セッションの保存先。
    /// - Returns: ライフサイクルモデル。
    private func makeModel(repository: any ConnectionSessionRepository) -> ConnectionSessionLifecycleModel {
        ConnectionSessionLifecycleModel(
            repository: repository,
            now: { [dates] in dates.now() },
            sessionEndPersisted: { [unowned self] in persistedEnds.append($0) }
        )
    }
}
