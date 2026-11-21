import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationTrack` の `isEmpty` と `watermark` を仕様から検証します。
final class ConnectionSessionLocationTrackTests: XCTestCase {
    /// 値生成の別名です。
    private typealias Values = ConnectionSessionLocationTrackValueFixtures

    /// サンプルも事象も無い軌跡は空で、水位は `.empty` です。
    ///
    /// 責務: 空の軌跡の `isEmpty` と `watermark` を確認します。
    func testEmptyTrackIsEmptyWithEmptyWatermark() throws {
        let track = try Values.track(ConnectionSessionID())

        XCTAssertTrue(track.isEmpty)
        XCTAssertEqual(track.watermark, .empty)
        XCTAssertEqual(ConnectionSessionLocationTrackWatermark.empty, Values.watermark(0, nil, 0, nil))
    }

    /// サンプルだけの軌跡は空ではなく、事象側の水位は 0 件・番号なしです。
    ///
    /// 責務: サンプルだけの `isEmpty` と、件数・最大 sequence を確認します。
    func testSamplesOnlyTrackIsNotEmptyAndCountsSamples() throws {
        let track = try Values.track(ConnectionSessionID(), sampleSequences: [0, 1, 2])

        XCTAssertFalse(track.isEmpty)
        XCTAssertEqual(track.watermark, Values.watermark(3, 2, 0, nil))
    }

    /// 事象だけの軌跡も空ではなく、サンプル側の水位は 0 件・番号なしです。
    ///
    /// 責務: 事象だけの `isEmpty` と、件数・最大 ordinal を確認します。
    func testEventsOnlyTrackIsNotEmptyAndCountsEvents() throws {
        let track = try Values.track(ConnectionSessionID(), eventOrdinals: [0, 1])

        XCTAssertFalse(track.isEmpty)
        XCTAssertEqual(track.watermark, Values.watermark(0, nil, 2, 1))
    }

    /// サンプルと事象の両方がある軌跡の水位は4項目すべてを持ちます。
    ///
    /// 責務: 両方がある時の件数と最大番号の組を確認します。
    func testTrackWithBothReportsAllWatermarkFields() throws {
        let track = try Values.track(ConnectionSessionID(), sampleSequences: [0, 1, 2, 3], eventOrdinals: [0, 1, 2])

        XCTAssertFalse(track.isEmpty)
        XCTAssertEqual(track.watermark, Values.watermark(4, 3, 3, 2))
    }

    /// 最大番号は件数から求めず、末尾の要素の番号です。
    ///
    /// 責務: 番号に歯抜けがあっても、最大 sequence と最大 ordinal が末尾の値になることを確認します。
    func testWatermarkUsesLastNumbersNotCounts() throws {
        let track = try Values.track(ConnectionSessionID(), sampleSequences: [4, 9], eventOrdinals: [2, 7, 11])

        XCTAssertEqual(track.watermark, Values.watermark(2, 9, 3, 11))
    }

    /// 1件だけの軌跡では件数 1、最大番号はその番号です。
    ///
    /// 責務: 境界の件数 1 で最大番号が 0 になることを確認します。
    func testSingleElementWatermark() throws {
        let track = try Values.track(ConnectionSessionID(), sampleSequences: [0], eventOrdinals: [0])

        XCTAssertEqual(track.watermark, Values.watermark(1, 0, 1, 0))
    }

    /// 内容が違えば軌跡は等しくなく、水位も異なります。
    ///
    /// 責務: 同じ件数でも最後の番号が違えば水位が等しくならないことを確認します。
    func testWatermarksDifferWhenLastNumberDiffersWithSameCount() throws {
        let sessionID = ConnectionSessionID()
        let first = try Values.track(sessionID, sampleSequences: [0, 1])
        let second = try Values.track(sessionID, sampleSequences: [0, 2])

        XCTAssertNotEqual(first.watermark, second.watermark)
        XCTAssertEqual(first.watermark.sampleCount, second.watermark.sampleCount)
    }
}
