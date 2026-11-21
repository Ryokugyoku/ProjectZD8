import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationProgressThrottle` が、段階が変わった時と、進み具合が1%以上進んだ時だけ通知させることを検証します。
///
/// 進み具合を段階の中の割合で測るか全体の割合で測るかは設計書で決まっていないため、どちらの測り方でも結果が同じになる値だけを使います。
@MainActor
final class RoadRegulationProgressThrottleTests: XCTestCase {
    /// 責務: 受信バイト(全体 100,000 B)のダウンロードの段階を作ります。
    private func downloading(_ received: Int64) -> RoadRegulationImportPhase {
        .downloading(RoadRegulationTransferProgress(receivedBytes: received, expectedBytes: 100_000))
    }

    /// 責務: 処理済みの圧縮バイト(全体 100,000 B)の取り込みの段階を作ります。
    private func importing(_ processed: Int64, imported: Int = 0) -> RoadRegulationImportPhase {
        .importing(RoadRegulationArchiveReadProgress(processedCompressedBytes: processed, totalCompressedBytes: 100_000), importedCount: imported)
    }

    /// 責務: 段階の列を順に渡し、通知させた数を返します。
    private func emittedCount(_ phases: [RoadRegulationImportPhase], throttle: inout RoadRegulationProgressThrottle) -> Int {
        phases.filter { throttle.shouldEmit($0) }.count
    }

    /// 最初の段階は必ず通知させます。
    ///
    /// 責務: 初めての呼び出しを確認します。
    func testFirstPhaseIsEmitted() {
        var throttle = RoadRegulationProgressThrottle()

        XCTAssertTrue(throttle.shouldEmit(.preparing))
    }

    /// 同じ値の段階が続けて来たら、2回目からは通知させません。
    ///
    /// 責務: 値の重複を抑えることを、進み具合のある段階と無い段階で確認します。
    func testRepeatedIdenticalPhaseIsSuppressed() {
        var throttle = RoadRegulationProgressThrottle()

        XCTAssertTrue(throttle.shouldEmit(downloading(10_000)))
        XCTAssertFalse(throttle.shouldEmit(downloading(10_000)))
        XCTAssertTrue(throttle.shouldEmit(.activating))
        XCTAssertFalse(throttle.shouldEmit(.activating))
    }

    /// 段階が変わった時は、進み具合の差が小さくても必ず通知させます。
    ///
    /// 責務: 準備 → 一覧 → ダウンロード → 取り込み → 有効化 → 掃除 の各切り替えを確認します。
    func testEveryPhaseChangeIsEmitted() {
        var throttle = RoadRegulationProgressThrottle()
        let phases: [RoadRegulationImportPhase] = [
            .preparing, .fetchingCatalog, downloading(100_000), importing(0), .activating, .cleaningUp,
        ]

        XCTAssertEqual(phases.map { throttle.shouldEmit($0) }, Array(repeating: true, count: phases.count))
    }

    /// 同じ段階で、0.5% だけ進んだ報告は通知させず、3% 進んだ報告は通知させます(ダウンロード)。
    ///
    /// 責務: ダウンロードの段階の間引きを、しきい値の両側の値で確認します。
    func testDownloadingProgressBelowAndAboveStep() {
        var throttle = RoadRegulationProgressThrottle()

        XCTAssertTrue(throttle.shouldEmit(downloading(20_000)))
        XCTAssertFalse(throttle.shouldEmit(downloading(20_500)))
        XCTAssertTrue(throttle.shouldEmit(downloading(23_500)))
    }

    /// 同じ段階で、0.5% だけ進んだ報告は通知させず、3% 進んだ報告は通知させます(取り込み)。
    ///
    /// 責務: 取り込みの段階の間引きを、しきい値の両側の値で確認します。
    func testImportingProgressBelowAndAboveStep() {
        var throttle = RoadRegulationProgressThrottle()

        XCTAssertTrue(throttle.shouldEmit(importing(50_000)))
        XCTAssertFalse(throttle.shouldEmit(importing(50_500)))
        XCTAssertTrue(throttle.shouldEmit(importing(53_500)))
    }

    /// 間引いた小さな進みが積もって、最後に通知した値から十分に進めば通知させます(直前の値ではなく最後に通知した値と比べる)。
    ///
    /// 責務: 0.1% ずつ30回(計3%)進めた時に、1回以上3回以下だけ通知させることを確認します。
    func testSmallStepsAccumulateFromLastEmittedValue() {
        var throttle = RoadRegulationProgressThrottle()
        XCTAssertTrue(throttle.shouldEmit(importing(0)))

        let count = emittedCount((1...30).map { importing(Int64($0) * 100) }, throttle: &throttle)

        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertLessThanOrEqual(count, 3)
    }

    /// 同じ段階で頻繁に(0.01% ずつ1,000回、計10%)報告しても、通知は10回以下に間引かれます。
    ///
    /// 責務: 頻繁な報告の間引きの上限を確認します。
    func testFrequentReportsAreThinned() {
        var throttle = RoadRegulationProgressThrottle()
        XCTAssertTrue(throttle.shouldEmit(downloading(0)))

        let count = emittedCount((1...1_000).map { downloading(Int64($0) * 10) }, throttle: &throttle)

        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertLessThanOrEqual(count, 10)
    }

    /// 間引いている途中でも、段階が変わればすぐ通知させ、その後の同じ段階の小さな進みは間引きます。
    ///
    /// 責務: 段階の切り替えで比較の起点が新しい段階に移ることを確認します。
    func testPhaseChangeResetsComparison() {
        var throttle = RoadRegulationProgressThrottle()

        XCTAssertTrue(throttle.shouldEmit(downloading(99_900)))
        XCTAssertTrue(throttle.shouldEmit(importing(0)))
        XCTAssertFalse(throttle.shouldEmit(importing(100)))
        XCTAssertTrue(throttle.shouldEmit(.activating))
    }

    /// 最小の刻みを大きくすると、その刻みに満たない進みは通知させません。
    ///
    /// 責務: `minimumFractionStep` が効くことを、10% の刻みに対する 3% と 30% の進みで確認します。
    func testCustomMinimumStepIsHonored() {
        var throttle = RoadRegulationProgressThrottle(minimumFractionStep: 0.1)

        XCTAssertTrue(throttle.shouldEmit(importing(10_000)))
        XCTAssertFalse(throttle.shouldEmit(importing(13_000)))
        XCTAssertTrue(throttle.shouldEmit(importing(40_000)))
    }

    /// 割合が最後に通知した値より戻った報告は、通知させません。
    ///
    /// 責務: 戻りを通知しないことを確認します。
    func testBackwardProgressIsNotEmitted() {
        var throttle = RoadRegulationProgressThrottle()

        XCTAssertTrue(throttle.shouldEmit(importing(50_000)))
        XCTAssertFalse(throttle.shouldEmit(importing(10_000)))
    }

    /// 取り込み済みの件数だけが変わった報告は、通知させません。
    ///
    /// 責務: 割合が同じで件数だけ違う時に抑えることを確認します。
    func testImportedCountChangeAloneIsSuppressed() {
        var throttle = RoadRegulationProgressThrottle()

        XCTAssertTrue(throttle.shouldEmit(importing(50_000, imported: 10)))
        XCTAssertFalse(throttle.shouldEmit(importing(50_000, imported: 2_000)))
    }

    /// 予定の大きさが分からない(割合が分からない)ダウンロードは、値が違えば通知させ、同じ値は抑えます。
    ///
    /// 責務: 割合が分からない時の扱いを確認します。
    func testUnknownFractionEmitsOnlyWhenValueChanges() {
        var throttle = RoadRegulationProgressThrottle()
        let first = RoadRegulationImportPhase.downloading(RoadRegulationTransferProgress(receivedBytes: 100, expectedBytes: nil))
        let second = RoadRegulationImportPhase.downloading(RoadRegulationTransferProgress(receivedBytes: 101, expectedBytes: nil))

        XCTAssertTrue(throttle.shouldEmit(first))
        XCTAssertFalse(throttle.shouldEmit(first))
        XCTAssertTrue(throttle.shouldEmit(second))
    }
}
