import XCTest
@testable import ProjectZD8

/// signpost adapterの匿名run識別子gateを検証します。
final class OSSignpostAcquisitionPerformanceAdapterTests: XCTestCase {
    /// 許可ASCIIだけのrun識別子を受理します。
    ///
    /// 責務: 承認済み形式のrun識別子を利用可能なsignpost adapterへ変換できることを確認します。
    func testFactoryAcceptsAnonymousASCIIIdentifier() {
        XCTAssertNotNil(
            OSSignpostAcquisitionPerformanceAdapter.makeIfValid(
                runIdentifier: "phase4h_2026-07-29.run-01"
            )
        )
    }

    /// 空、固有情報を含み得る記号、非ASCII、過長入力を拒否します。
    ///
    /// 責務: privacy契約外のrun識別子をsignpost出力開始前に拒否することを確認します。
    func testFactoryRejectsInvalidIdentifiers() {
        XCTAssertNil(OSSignpostAcquisitionPerformanceAdapter.makeIfValid(runIdentifier: nil))
        XCTAssertNil(OSSignpostAcquisitionPerformanceAdapter.makeIfValid(runIdentifier: ""))
        XCTAssertNil(OSSignpostAcquisitionPerformanceAdapter.makeIfValid(runIdentifier: "vehicle/id"))
        XCTAssertNil(OSSignpostAcquisitionPerformanceAdapter.makeIfValid(runIdentifier: "実車run"))
        XCTAssertNil(
            OSSignpostAcquisitionPerformanceAdapter.makeIfValid(
                runIdentifier: String(repeating: "a", count: 65)
            )
        )
    }

    /// no-op portが固定tokenを返して全通知を受理します。
    ///
    /// 責務: 通常buildの既定計測境界が取得操作へ副作用を追加しないことを確認します。
    func testNoOpPortAcceptsCompleteIntervalLifecycle() {
        let port = NoOpAcquisitionPerformanceEventPort()
        let interval = port.begin(
            .batchAcquisition,
            context: AcquisitionPerformanceContext(generation: 1, batchOrdinal: 0)
        )

        port.queueDidEnter(interval)
        port.end(interval, outcome: .succeeded)

        XCTAssertEqual(interval.identifier, 0)
        XCTAssertEqual(interval.operation, .batchAcquisition)
    }
}
