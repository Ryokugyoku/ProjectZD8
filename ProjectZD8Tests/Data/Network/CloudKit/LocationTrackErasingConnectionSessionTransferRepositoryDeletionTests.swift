import CloudKit
import Foundation
import XCTest
@testable import ProjectZD8

/// 軌跡の削除を足すデコレーターが、`deleteSession` と `deleteAll` を「base → 軌跡」の順に実行し、
/// どちらの失敗もエラーを包まずに伝えることを検証します。
@MainActor
final class LocationTrackErasingConnectionSessionTransferRepositoryDeletionTests: XCTestCase {
    /// テストで注入するエラーです。
    private enum InjectedError: Error, Equatable {
        /// base の失敗です。
        case base
        /// 軌跡側の失敗です。
        case locationTracks
    }

    /// 呼び出すアカウントです。
    private static let account = "account-a"

    /// base の Spy です。
    private let base = RecordingConnectionSessionTransferRepositorySpy()
    /// 軌跡側の Fake です。
    private let locationTracks = ConnectionSessionLocationTrackCloudRepositoryFake()
    /// 削除するセッションです。
    private let sessionID = ConnectionSessionID()
    /// base と軌跡側の呼び出しの順序です。
    private var order: [String] = []

    /// 責務: base と軌跡側の呼び出しを、1つの順序の記録へつなぎます。
    override func setUp() async throws {
        try await super.setUp()
        base.onCall = { [unowned self] _ in self.order.append("base") }
        locationTracks.onCall = { [unowned self] _ in self.order.append("locationTracks") }
    }

    /// `deleteSession` は、同じ引数で base を呼んでから軌跡側の削除を呼びます。
    ///
    /// 責務: 順序が base → 軌跡で、どちらにも同じセッションとアカウントが渡ることを確認します。
    func testDeleteSessionCallsBaseThenLocationTracksWithSameArguments() async throws {
        try await makeRepository().deleteSession(sessionID, for: Self.account)

        XCTAssertEqual(order, ["base", "locationTracks"])
        XCTAssertEqual(base.calls, [.deleteSession(sessionID, accountIdentifier: Self.account)])
        XCTAssertEqual(locationTracks.calls, [.delete(sessionID: sessionID, accountIdentifier: Self.account)])
    }

    /// `deleteAll` は、同じアカウントで base を呼んでから軌跡側の全削除を呼びます。
    ///
    /// 責務: 順序が base → 軌跡で、どちらにも同じアカウントが渡ることを確認します。
    func testDeleteAllCallsBaseThenLocationTracksWithSameAccount() async throws {
        try await makeRepository().deleteAll(for: Self.account)

        XCTAssertEqual(order, ["base", "locationTracks"])
        XCTAssertEqual(base.calls, [.deleteAll(accountIdentifier: Self.account)])
        XCTAssertEqual(locationTracks.calls, [.deleteAll(accountIdentifier: Self.account)])
    }

    /// `deleteSession` で base が失敗したら、軌跡側を呼ばずに同じエラーを投げます。
    ///
    /// 責務: base のエラーが包まれずに伝わり、軌跡側の呼び出しが0件であることを確認します。
    func testDeleteSessionBaseFailureSkipsLocationTracksAndRethrows() async {
        base.error = InjectedError.base

        let error = await deleteSessionExpectingError()

        XCTAssertEqual(error as? InjectedError, .base)
        XCTAssertEqual(locationTracks.calls, [])
    }

    /// `deleteAll` で base が失敗したら、軌跡側を呼ばずに同じエラーを投げます。
    ///
    /// 責務: base のエラーが包まれずに伝わり、軌跡側の呼び出しが0件であることを確認します。
    func testDeleteAllBaseFailureSkipsLocationTracksAndRethrows() async {
        base.error = InjectedError.base

        let error = await deleteAllExpectingError()

        XCTAssertEqual(error as? InjectedError, .base)
        XCTAssertEqual(locationTracks.calls, [])
    }

    /// `deleteSession` で軌跡側が失敗したら、そのエラーを同じ型・同じ値のまま投げます。
    ///
    /// 責務: base の削除の後に起きた軌跡側のエラーが、包まれずに伝わることを確認します。
    func testDeleteSessionLocationTrackFailurePropagatesUnwrapped() async {
        locationTracks.setFailure(InjectedError.locationTracks, for: .delete)

        let error = await deleteSessionExpectingError()

        XCTAssertEqual(error as? InjectedError, .locationTracks)
        XCTAssertEqual(order, ["base", "locationTracks"])
    }

    /// `deleteSession` で軌跡側が CKError で失敗したら、CKError のまま投げます。
    ///
    /// 責務: アカウント削除の失敗の分類が使う CKError の code が保たれることを確認します。
    func testDeleteSessionLocationTrackCloudKitErrorKeepsCode() async {
        locationTracks.setFailure(CKError(.zoneBusy), for: .delete)

        let error = await deleteSessionExpectingError()

        XCTAssertEqual((error as? CKError)?.code, .zoneBusy)
        XCTAssertEqual(error.map { ($0 as NSError).domain }, CKErrorDomain)
    }

    /// `deleteAll` で軌跡側が CKError で失敗したら、CKError のまま投げます。
    ///
    /// 責務: base の全削除の後に起きた軌跡側の CKError が、型と code を保って伝わることを確認します。
    func testDeleteAllLocationTrackCloudKitErrorPropagatesUnwrapped() async {
        locationTracks.setFailure(CKError(.networkFailure), for: .deleteAll)

        let error = await deleteAllExpectingError()

        XCTAssertEqual((error as? CKError)?.code, .networkFailure)
        XCTAssertEqual(error.map { ($0 as NSError).domain }, CKErrorDomain)
        XCTAssertEqual(order, ["base", "locationTracks"])
    }

    /// `deleteAll` で軌跡側が失敗したら、そのエラーを同じ型・同じ値のまま投げます。
    ///
    /// 責務: 独自のエラー型でも包まれずに伝わることを確認します。
    func testDeleteAllLocationTrackFailurePropagatesUnwrapped() async {
        locationTracks.setFailure(InjectedError.locationTracks, for: .deleteAll)

        let error = await deleteAllExpectingError()

        XCTAssertEqual(error as? InjectedError, .locationTracks)
        XCTAssertEqual(base.calls, [.deleteAll(accountIdentifier: Self.account)])
    }

    /// テスト対象のデコレーターを作ります。
    ///
    /// 責務: Spy の base と Fake の軌跡側で包みます。
    /// - Returns: デコレーター。
    private func makeRepository() -> LocationTrackErasingConnectionSessionTransferRepository {
        LocationTrackErasingConnectionSessionTransferRepository(base: base, locationTracks: locationTracks)
    }

    /// 失敗するはずの `deleteSession` を行い、投げられたエラーを返します。
    ///
    /// 責務: 成功した場合はテストを失敗させ、`nil` を返します。
    /// - Returns: 投げられたエラー。成功した場合は `nil`。
    private func deleteSessionExpectingError() async -> (any Error)? {
        do {
            try await makeRepository().deleteSession(sessionID, for: Self.account)
            XCTFail("deleteSession は失敗する必要があります")
            return nil
        } catch {
            return error
        }
    }

    /// 失敗するはずの `deleteAll` を行い、投げられたエラーを返します。
    ///
    /// 責務: 成功した場合はテストを失敗させ、`nil` を返します。
    /// - Returns: 投げられたエラー。成功した場合は `nil`。
    private func deleteAllExpectingError() async -> (any Error)? {
        do {
            try await makeRepository().deleteAll(for: Self.account)
            XCTFail("deleteAll は失敗する必要があります")
            return nil
        } catch {
            return error
        }
    }
}
