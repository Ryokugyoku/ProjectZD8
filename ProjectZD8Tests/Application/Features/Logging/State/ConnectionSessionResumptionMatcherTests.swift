import Foundation
import XCTest
@testable import ProjectZD8

/// プロセス復帰後の続行可能なセッションを次の接続で続けるかの判定を検証します。
///
/// 終端(アダプター)の一致は、実装のDocCの宣言どおり判定に使いません(接続セッションが終端を保存しないため)。
final class ConnectionSessionResumptionMatcherTests: XCTestCase {
    /// 最後にcommitした実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 10_000)
    /// 登録済みの車両IDです。
    private let vehicle = VehicleID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    /// 別の登録済みの車両IDです。
    private let otherVehicle = VehicleID(rawValue: UUID(uuidString: "66666666-7777-8888-9999-000000000000")!)

    /// 車両の組合せごとに、猶予内なら同じ登録車両同士と未登録同士だけが続行です。
    ///
    /// 責務: 同じ登録車両・別の登録車両・登録済みと未登録(両方向)・未登録同士の5つの組合せを確認します。
    func testVehicleCombinationsWithinGrace() {
        let cases: [(VehicleID?, VehicleID?, Bool)] = [
            (vehicle, vehicle, true),
            (vehicle, otherVehicle, false),
            (vehicle, nil, false),
            (nil, vehicle, false),
            (nil, nil, true)
        ]
        for (resumable, connecting, expected) in cases {
            XCTAssertEqual(canResume(resumable, connecting, after: 60), expected, "\(String(describing: resumable)) \(String(describing: connecting))")
        }
    }

    /// 車両が一致しても、猶予の直後と時計の逆行では続けず、ちょうど猶予までは続けます。
    ///
    /// 責務: 登録車両同士と未登録同士で、実時間の猶予の境界を確認します。
    func testGraceBoundariesForMatchingVehicles() {
        for id in [Optional(vehicle), nil] {
            XCTAssertTrue(canResume(id, id, after: 0))
            XCTAssertTrue(canResume(id, id, after: 180))
            XCTAssertFalse(canResume(id, id, after: 180.001))
            XCTAssertFalse(canResume(id, id, after: -1))
        }
    }

    /// 判定を呼びます。
    ///
    /// 責務: 最後のcommitから指定秒後の時点で続行判定を返します。
    /// - Parameters:
    ///   - resumable: 続行可能なセッションの車両ID。
    ///   - connecting: 次の接続の車両ID。
    ///   - seconds: 最後のcommitからの経過秒。
    /// - Returns: 続ける場合は `true`。
    private func canResume(_ resumable: VehicleID?, _ connecting: VehicleID?, after seconds: TimeInterval) -> Bool {
        ConnectionSessionResumptionMatcher().canResume(
            resumableVehicleID: resumable,
            connectingVehicleID: connecting,
            lastCommittedAt: lastCommittedAt,
            now: lastCommittedAt.addingTimeInterval(seconds)
        )
    }
}
