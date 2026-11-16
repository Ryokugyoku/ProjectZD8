import XCTest
@testable import ProjectZD8

/// `AccountDeletionMarkerGate` が、印の有無と確認の失敗を仕様どおりに扱うことを検証します。
///
/// 仕様: 印があれば `onAccountDeleted` を1回呼んで `accountDeleted` を投げる。印がなければ何もしない。確認自体の失敗は成功扱いにせず投げ直す。
@MainActor
final class AccountDeletionMarkerGateTests: XCTestCase {
    /// 確認の失敗を表す検証用エラーです。
    private struct CheckFailure: Error, Equatable {}

    /// 印があれば、ログアウト通知を1回だけ呼び、`accountDeleted` を投げることを検証します。
    ///
    /// 責務: 通知の回数と引数、投げるエラーの種類を確認します。
    func testMarkerPresentNotifiesOnceAndThrowsAccountDeleted() async {
        let marker = AccountDeletionMarkerPortFake()
        marker.deletedAccounts = ["user"]
        let gate = AccountDeletionMarkerGate(marker: marker)
        var notified: [String] = []
        gate.onAccountDeleted = { notified.append($0) }

        do {
            try await gate.ensureAccountNotDeleted(for: "user")
            XCTFail("印があるのに確認が成功しました。")
        } catch {
            XCTAssertEqual(error as? AccountDeletionMarkerError, .accountDeleted)
        }

        XCTAssertEqual(notified, ["user"])
        XCTAssertEqual(marker.checkedAccounts, ["user"])
    }

    /// 印がなければ何もせず、ログアウト通知も呼ばないことを検証します。
    ///
    /// 責務: 印なしの確認が成功し、通知が0回であることを確認します。
    func testNoMarkerDoesNothing() async throws {
        let marker = AccountDeletionMarkerPortFake()
        let gate = AccountDeletionMarkerGate(marker: marker)
        var notified: [String] = []
        gate.onAccountDeleted = { notified.append($0) }

        try await gate.ensureAccountNotDeleted(for: "user")

        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(marker.checkedAccounts, ["user"])
    }

    /// 別アカウントの印は対象に影響しないことを検証します。
    ///
    /// 責務: 印があるのが他アカウントだけなら、確認対象は成功することを確認します。
    func testMarkerOfAnotherAccountDoesNotAffectThisAccount() async throws {
        let marker = AccountDeletionMarkerPortFake()
        marker.deletedAccounts = ["other"]
        let gate = AccountDeletionMarkerGate(marker: marker)
        var notified: [String] = []
        gate.onAccountDeleted = { notified.append($0) }

        try await gate.ensureAccountNotDeleted(for: "user")

        XCTAssertTrue(notified.isEmpty)
    }

    /// 確認自体が失敗したら、そのエラーを投げ直し、ログアウト通知は呼ばないことを検証します。
    ///
    /// 責務: 確認できない場合を成功扱いにも削除済み扱いにもしないことを確認します。
    func testCheckFailureIsRethrownAndDoesNotNotify() async {
        let marker = AccountDeletionMarkerPortFake()
        marker.isDeletedError = CheckFailure()
        let gate = AccountDeletionMarkerGate(marker: marker)
        var notified: [String] = []
        gate.onAccountDeleted = { notified.append($0) }

        do {
            try await gate.ensureAccountNotDeleted(for: "user")
            XCTFail("確認が失敗したのに成功扱いになりました。")
        } catch {
            XCTAssertEqual(error as? CheckFailure, CheckFailure())
        }

        XCTAssertTrue(notified.isEmpty)
    }

    /// 通知先が未設定でも、印があれば `accountDeleted` を投げることを検証します。
    ///
    /// 責務: `onAccountDeleted` が nil の時にアップロードを許してしまわないことを確認します。
    func testMarkerPresentWithoutHandlerStillThrows() async {
        let marker = AccountDeletionMarkerPortFake()
        marker.deletedAccounts = ["user"]
        let gate = AccountDeletionMarkerGate(marker: marker)

        do {
            try await gate.ensureAccountNotDeleted(for: "user")
            XCTFail("印があるのに確認が成功しました。")
        } catch {
            XCTAssertEqual(error as? AccountDeletionMarkerError, .accountDeleted)
        }
    }
}
