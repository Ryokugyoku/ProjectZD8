import Foundation
import XCTest
@testable import ProjectZD8

/// `LoadVehicleUnknownConnectionSessionsUseCase` が保存先の照会結果を返し、失敗を空の一覧に潰さないことを検証します。
///
/// 仕様: U4 受け入れ条件 11・15。
final class LoadVehicleUnknownConnectionSessionsUseCaseTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = VehicleUnknownSessionFixture

    /// 指定アカウントで照会し、保存先の並びのまま返します。
    ///
    /// 責務: 照会の引数がアカウント識別子で、戻り値が保存先の一覧と同じであることを確認します。
    func testReturnsRepositorySessionsForAccount() throws {
        let repository = VehicleUnknownConnectionSessionRepositoryFake()
        let sessions = [F.session(startedAt: 300), F.session(startedAt: 100)]
        repository.sessionsByAccount[F.accountIdentifier] = sessions

        let loaded = try LoadVehicleUnknownConnectionSessionsUseCase(repository: repository).execute(accountIdentifier: F.accountIdentifier)

        XCTAssertEqual(loaded, sessions)
        XCTAssertEqual(repository.loadQueries, [F.accountIdentifier])
    }

    /// 該当が無ければ空の一覧を返します。
    ///
    /// 責務: 0件の境界で空配列になることを確認します。
    func testReturnsEmptyWhenNothingMatches() throws {
        let repository = VehicleUnknownConnectionSessionRepositoryFake()
        XCTAssertEqual(try LoadVehicleUnknownConnectionSessionsUseCase(repository: repository).execute(accountIdentifier: "nobody"), [])
    }

    /// 保存先の失敗はそのまま投げます。
    ///
    /// 責務: 照会の失敗が空の一覧ではなく同じエラーとして伝わることを確認します(受け入れ条件 15)。
    func testPropagatesRepositoryFailure() {
        let repository = VehicleUnknownConnectionSessionRepositoryFake()
        repository.loadFailure = VehicleUnknownSessionTestError.storageFailed

        XCTAssertThrowsError(try LoadVehicleUnknownConnectionSessionsUseCase(repository: repository).execute(accountIdentifier: "account")) {
            XCTAssertEqual($0 as? VehicleUnknownSessionTestError, .storageFailed)
        }
    }

    /// DB準備不可の保存先では、空ではなく利用不能として失敗します。
    ///
    /// 責務: `UnavailableConnectionSessionRepository` を使った照会が `unavailable` を投げることを確認します(受け入れ条件 15)。
    func testUnavailableRepositoryFails() {
        let useCase = LoadVehicleUnknownConnectionSessionsUseCase(repository: UnavailableConnectionSessionRepository())
        XCTAssertThrowsError(try useCase.execute(accountIdentifier: "account")) {
            XCTAssertEqual($0 as? ConnectionSessionRepositoryError, .unavailable)
        }
    }
}
