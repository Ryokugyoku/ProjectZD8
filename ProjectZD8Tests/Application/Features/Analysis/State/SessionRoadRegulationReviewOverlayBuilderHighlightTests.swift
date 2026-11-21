import Foundation
import XCTest
@testable import ProjectZD8

/// 重ね合わせの強調の範囲(選択なし・選択あり・存在しない id・余白)を検証します(設計書 §3.4 Overlays、§7 TC1b)。
///
/// 範囲は基準からの秒に直し、誤差 1e-6 秒で比べます。
@MainActor
final class SessionRoadRegulationReviewOverlayBuilderHighlightTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues

    /// 余白を指定した検証対象を作ります。
    ///
    /// 責務: 文言をキーの `<キー>` に解決する builder を返します。
    /// - Parameter padding: 前後の余白の秒。
    /// - Returns: builder。
    private func builder(padding: TimeInterval = 0.5) -> SessionRoadRegulationReviewOverlayBuilder {
        SessionRoadRegulationReviewOverlayBuilder(highlightPaddingSeconds: padding, localize: Values.bracketLocalize)
    }

    /// 最高速度と一時停止に、強調される行とされない行を混ぜた入力です。
    ///
    /// 責務: possibleIssue が id の順でない並び、compliant・undeterminable を含む行を返します。
    /// - Returns: 行。
    private func rows() -> [SessionRoadRegulationReviewRow] {
        [
            Values.row(id: 2, kind: .speedLimit, outcome: .possibleIssue, seconds: 20...30),
            Values.row(id: 0, kind: .speedLimit, outcome: .possibleIssue, seconds: 0...5),
            Values.row(id: 1, kind: .speedLimit, outcome: .compliant, seconds: 10...12),
            Values.row(id: 3, kind: .speedLimit, outcome: .undeterminable, seconds: 40...41),
            Values.row(id: 4, kind: .stop, outcome: .possibleIssue, seconds: 50...51),
            Values.row(id: 5, kind: .stop, outcome: .compliant, seconds: 60...61)
        ]
    }

    /// 重ね合わせの強調の範囲を、基準からの秒の組で返します。
    ///
    /// 責務: 種類の重ね合わせを id で探し、範囲を比べやすい秒の組にします。
    /// - Parameters:
    ///   - overlays: 重ね合わせ。
    ///   - id: 重ね合わせの id。
    /// - Returns: (下端, 上端) の秒。見つからなければ nil。
    private func seconds(_ overlays: [RouteAnalysisOverlay], _ id: String) -> [(Double, Double)]? {
        overlays.first { $0.id == id }?.highlightedTimeRanges.map {
            ($0.lowerBound.timeIntervalSince(Values.base), $0.upperBound.timeIntervalSince(Values.base))
        }
    }

    /// 秒の組を誤差つきで比べます。
    ///
    /// 責務: 件数と各端を 1e-6 秒の誤差で比べ、違えば失敗させます。
    /// - Parameters:
    ///   - actual: 実際の範囲。
    ///   - expected: 期待する範囲。
    ///   - line: 失敗を報告する行。
    private func assertRanges(_ actual: [(Double, Double)]?, _ expected: [(Double, Double)], line: UInt = #line) {
        guard let actual else {
            return XCTFail("重ね合わせがありません", line: line)
        }
        XCTAssertEqual(actual.count, expected.count, line: line)
        for (got, want) in zip(actual, expected) {
            XCTAssertEqual(got.0, want.0, accuracy: 1e-6, line: line)
            XCTAssertEqual(got.1, want.1, accuracy: 1e-6, line: line)
        }
    }

    /// 責務: 選択なしでは possibleIssue の範囲だけを前後 0.5 秒広げ、id の昇順に並べる(compliant・undeterminable は入らない)ことを確かめます。
    func testNoSelectionHighlightsPossibleIssuesInIDOrder() {
        let overlays = builder().overlays(for: rows(), selectedRowID: nil)

        assertRanges(seconds(overlays, "road_regulation.speed_limit"), [(-0.5, 5.5), (19.5, 30.5)])
        assertRanges(seconds(overlays, "road_regulation.stop"), [(49.5, 51.5)])
    }

    /// 責務: possibleIssue の無い種類は、選択なしで強調が空であることを確かめます。
    func testKindWithoutIssuesHasNoHighlight() {
        let input = [Values.row(id: 0, kind: .oneWay, outcome: .compliant), Values.row(id: 1, kind: .oneWay, outcome: .undeterminable)]

        assertRanges(seconds(builder().overlays(for: input, selectedRowID: nil), "road_regulation.one_way"), [])
    }

    /// 責務: 重なる possibleIssue の範囲を併合せず、2つのまま返すことを確かめます。
    func testOverlappingRangesAreNotMerged() {
        let input = [
            Values.row(id: 0, kind: .oneWay, outcome: .possibleIssue, seconds: 0...10),
            Values.row(id: 1, kind: .oneWay, outcome: .possibleIssue, seconds: 5...15)
        ]

        assertRanges(seconds(builder().overlays(for: input, selectedRowID: nil), "road_regulation.one_way"), [(-0.5, 10.5), (4.5, 15.5)])
    }

    /// 責務: 選んだ行(compliant でも)の種類は、その行の範囲1つだけを広げて返し、他の種類は選択なしと同じであることを確かめます。
    func testSelectionHighlightsOnlySelectedRowInItsKind() {
        let overlays = builder().overlays(for: rows(), selectedRowID: 1)

        assertRanges(seconds(overlays, "road_regulation.speed_limit"), [(9.5, 12.5)])
        assertRanges(seconds(overlays, "road_regulation.stop"), [(49.5, 51.5)])
    }

    /// 責務: 選択は強調だけを変え、run と凡例は選択なしと同じであることを確かめます。
    func testSelectionDoesNotChangeRunsOrLegend() {
        let plain = builder().overlays(for: rows(), selectedRowID: nil)
        let selected = builder().overlays(for: rows(), selectedRowID: 5)

        XCTAssertEqual(selected.map(\.runs), plain.map(\.runs))
        XCTAssertEqual(selected.map(\.legend), plain.map(\.legend))
        assertRanges(seconds(selected, "road_regulation.stop"), [(59.5, 61.5)])
    }

    /// 責務: 存在しない id の選択は、全種類で選択なしと同じ結果になることを確かめます。
    func testUnknownSelectionBehavesAsNoSelection() {
        let plain = builder().overlays(for: rows(), selectedRowID: nil)
        let unknown = builder().overlays(for: rows(), selectedRowID: 99)

        XCTAssertEqual(unknown, plain)
        assertRanges(seconds(unknown, "road_regulation.speed_limit"), [(-0.5, 5.5), (19.5, 30.5)])
    }

    /// 責務: 余白 0 秒では範囲を広げないことを確かめます。
    func testZeroPaddingKeepsRowRanges() {
        let overlays = builder(padding: 0).overlays(for: rows(), selectedRowID: nil)

        assertRanges(seconds(overlays, "road_regulation.speed_limit"), [(0, 5), (20, 30)])
    }

    /// 責務: 余白が負・NaN・∞ の時は 0 として扱い、範囲を広げも縮めもしないことを確かめます(管理役の確定事項)。
    func testInvalidPaddingIsTreatedAsZero() {
        for padding in [-1.0, Double.nan, Double.infinity] {
            let overlays = builder(padding: padding).overlays(for: rows(), selectedRowID: nil)

            assertRanges(seconds(overlays, "road_regulation.stop"), [(50, 51)])
        }
    }
}
