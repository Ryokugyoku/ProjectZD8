import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両のログ集計 `UnassignedObservedVINSummary` の車両数・件数・最新VINを検証します。
@MainActor
final class UnassignedObservedVINSummaryTests: XCTestCase {
    /// 集計に使うセッションを作ります。
    private typealias Fixture = UnassignedObservedVINSessionFixture

    /// 0件では集計を作りません。
    ///
    /// 責務: 空の照会結果が `nil` になる境界を確認します。
    func testEmptySessionsProduceNoSummary() {
        XCTAssertNil(UnassignedObservedVINSummary(sessions: []))
    }

    /// 1台1件では車両1台・ログ1件です。
    ///
    /// 責務: 最小の非空入力での3つの値を確認します。
    func testOneVehicleOneLog() throws {
        let summary = try XCTUnwrap(UnassignedObservedVINSummary(sessions: [Fixture.session(vin: Fixture.firstVIN, startedAt: 10)]))
        XCTAssertEqual(summary.vehicleCount, 1)
        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.latestVIN, Fixture.firstVIN)
    }

    /// 同じVINのログが複数あれば車両1台・ログ複数件です。
    ///
    /// 責務: VINの種類数とセッション数が別々に数えられることを確認します。
    func testOneVehicleManyLogs() throws {
        let sessions = [10, 20, 30].map { Fixture.session(vin: Fixture.firstVIN, startedAt: $0) }
        let summary = try XCTUnwrap(UnassignedObservedVINSummary(sessions: sessions))
        XCTAssertEqual(summary.vehicleCount, 1)
        XCTAssertEqual(summary.sessionCount, 3)
    }

    /// 大文字小文字だけが違うVINは同じ車両として数えます。
    ///
    /// 責務: 小文字・大文字・混在のVINが1台に数えられ、件数は3件のままであることを確認します。
    func testVINsDifferingOnlyInCaseCountAsOneVehicle() throws {
        let mixed = "jf1ZD8a11p9000001"
        let sessions = [
            Fixture.session(vin: Fixture.firstVIN, startedAt: 10),
            Fixture.session(vin: Fixture.firstVIN.lowercased(), startedAt: 20),
            Fixture.session(vin: mixed, startedAt: 30)
        ]
        let summary = try XCTUnwrap(UnassignedObservedVINSummary(sessions: sessions))
        XCTAssertEqual(summary.vehicleCount, 1)
        XCTAssertEqual(summary.sessionCount, 3)
    }

    /// 異なるVINが複数あれば、その種類数が車両数です。
    ///
    /// 責務: 3種類のVINと5件のセッションから車両3台・ログ5件になることを確認します。
    func testManyVehicles() throws {
        let sessions = [
            Fixture.session(vin: Fixture.firstVIN, startedAt: 10),
            Fixture.session(vin: Fixture.secondVIN, startedAt: 20),
            Fixture.session(vin: Fixture.firstVIN, startedAt: 30),
            Fixture.session(vin: Fixture.thirdVIN, startedAt: 40),
            Fixture.session(vin: Fixture.secondVIN.lowercased(), startedAt: 50)
        ]
        let summary = try XCTUnwrap(UnassignedObservedVINSummary(sessions: sessions))
        XCTAssertEqual(summary.vehicleCount, 3)
        XCTAssertEqual(summary.sessionCount, 5)
    }

    /// 登録画面へ引き渡すVINは、入力順に関係なく最も新しく開始したセッションのVINです。
    ///
    /// 責務: 最新が先頭・中央・末尾のいずれにあっても同じVINが選ばれることを確認します。
    func testLatestVINIsFromNewestSessionRegardlessOfOrder() throws {
        let newest = Fixture.session(vin: Fixture.secondVIN, startedAt: 300)
        let older = Fixture.session(vin: Fixture.firstVIN, startedAt: 100)
        let middle = Fixture.session(vin: Fixture.thirdVIN, startedAt: 200)
        for sessions in [[newest, older, middle], [older, newest, middle], [older, middle, newest]] {
            let summary = try XCTUnwrap(UnassignedObservedVINSummary(sessions: sessions))
            XCTAssertEqual(summary.latestVIN, Fixture.secondVIN)
        }
    }
}
