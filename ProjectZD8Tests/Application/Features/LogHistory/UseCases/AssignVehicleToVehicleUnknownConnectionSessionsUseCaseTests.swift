import Foundation
import XCTest
@testable import ProjectZD8

/// `AssignVehicleToVehicleUnknownConnectionSessionsUseCase` の紐付けの引数・件数・履歴の再読込の通知・失敗の伝播を検証します。
///
/// 仕様: U4 受け入れ条件 12・14・15。後続処理は既存の観測VINの紐付けと同じく、1件以上更新した時だけ履歴の再読込を通知します。
@MainActor
final class AssignVehicleToVehicleUnknownConnectionSessionsUseCaseTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = VehicleUnknownSessionFixture

    /// 履歴の再読込の通知回数です。
    private var historyChangeCount = 0

    /// 責務: 通知回数を戻します。
    override func tearDown() async throws {
        historyChangeCount = 0
        try await super.tearDown()
    }

    /// 検証対象を作ります。
    ///
    /// 責務: 履歴の再読込の通知を数える処理を結び付けます。
    /// - Parameter repository: 保存先。
    /// - Returns: 検証対象。
    private func makeUseCase(_ repository: any VehicleUnknownConnectionSessionRepository) -> AssignVehicleToVehicleUnknownConnectionSessionsUseCase {
        AssignVehicleToVehicleUnknownConnectionSessionsUseCase(repository: repository) { [weak self] in self?.historyChangeCount += 1 }
    }

    /// 車両の表示情報・選んだID・アカウントで保存先を呼び、更新件数を返します。
    ///
    /// 責務: 保存先へ渡す3つの引数と戻り値の受け渡しを確認します。
    func testCallsRepositoryWithVehicleSnapshotIDsAndAccount() throws {
        let repository = VehicleUnknownConnectionSessionRepositoryFake()
        let sessions = [F.session(startedAt: 100), F.session(startedAt: 200)]
        repository.sessionsByAccount[F.accountIdentifier] = sessions
        let ids = sessions.map(\.id)

        let count = try makeUseCase(repository).execute(vehicle: F.vehicle, sessionIDs: ids, accountIdentifier: F.accountIdentifier)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(repository.assignCalls, [.init(
            vehicle: ConnectionSessionVehicle(profile: F.vehicle),
            sessionIDs: ids,
            accountIdentifier: F.accountIdentifier
        )])
    }

    /// 1件以上紐付けたら、件数によらず履歴の再読込を1回通知します。
    ///
    /// 責務: 1件と2件の紐付けで通知がそれぞれ1回であることを確認します(受け入れ条件 14)。
    func testNotifiesHistoryOnceWhenAssigned() throws {
        for count in [1, 2] {
            historyChangeCount = 0
            let repository = VehicleUnknownConnectionSessionRepositoryFake()
            let sessions = (0..<count).map { F.session(startedAt: Double($0)) }
            repository.sessionsByAccount[F.accountIdentifier] = sessions

            _ = try makeUseCase(repository).execute(vehicle: F.vehicle, sessionIDs: sessions.map(\.id), accountIdentifier: F.accountIdentifier)

            XCTAssertEqual(historyChangeCount, 1, "\(count)件")
        }
    }

    /// 1件も紐付けなかった(対象外・存在しないID)場合は0を返し、通知しません。
    ///
    /// 責務: 更新0件の境界で履歴の再読込を通知しないことを確認します(受け入れ条件 13・14)。
    func testDoesNotNotifyWhenNothingAssigned() throws {
        let repository = VehicleUnknownConnectionSessionRepositoryFake()

        let count = try makeUseCase(repository).execute(
            vehicle: F.vehicle, sessionIDs: [ConnectionSessionID()], accountIdentifier: F.accountIdentifier
        )

        XCTAssertEqual(count, 0)
        XCTAssertEqual(historyChangeCount, 0)
    }

    /// 保存先の失敗はそのまま投げ、通知しません。
    ///
    /// 責務: 紐付けの失敗が成功や0件に潰されず、同じエラーとして伝わることを確認します(受け入れ条件 15)。
    func testPropagatesRepositoryFailureWithoutNotifying() {
        let repository = VehicleUnknownConnectionSessionRepositoryFake()
        repository.assignFailure = VehicleUnknownSessionTestError.storageFailed

        XCTAssertThrowsError(try makeUseCase(repository).execute(
            vehicle: F.vehicle, sessionIDs: [ConnectionSessionID()], accountIdentifier: F.accountIdentifier
        )) {
            XCTAssertEqual($0 as? VehicleUnknownSessionTestError, .storageFailed)
        }
        XCTAssertEqual(historyChangeCount, 0)
    }

    /// DB準備不可の保存先では、0件ではなく利用不能として失敗します。
    ///
    /// 責務: `UnavailableConnectionSessionRepository` を使った紐付けが `unavailable` を投げ、通知しないことを確認します(受け入れ条件 15)。
    func testUnavailableRepositoryFails() {
        XCTAssertThrowsError(try makeUseCase(UnavailableConnectionSessionRepository()).execute(
            vehicle: F.vehicle, sessionIDs: [ConnectionSessionID()], accountIdentifier: F.accountIdentifier
        )) {
            XCTAssertEqual($0 as? ConnectionSessionRepositoryError, .unavailable)
        }
        XCTAssertEqual(historyChangeCount, 0)
    }
}
