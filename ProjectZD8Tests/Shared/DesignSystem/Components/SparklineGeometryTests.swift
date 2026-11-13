import CoreGraphics
import XCTest
@testable import ProjectZD8

/// `SparklineGeometry` の欠損分割・レンジ決定の検証。
final class SparklineGeometryTests: XCTestCase {
    private let size = CGSize(width: 100, height: 10)

    func testGapsSplitSegmentsInsteadOfBridging() {
        let segments = SparklineGeometry.segments(values: [1, 2, nil, nil, 3, 4], range: 0...4, size: size)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].points.count, 2)
        XCTAssertEqual(segments[1].points.count, 2)
        XCTAssertEqual(segments[0].points[0].x, 0, accuracy: 0.001)
        XCTAssertEqual(segments[1].points[1].x, 100, accuracy: 0.001)
    }

    func testAllMissingYieldsNoSegments() {
        XCTAssertTrue(SparklineGeometry.segments(values: [nil, nil], range: 0...1, size: size).isEmpty)
        XCTAssertTrue(SparklineGeometry.segments(values: [], range: 0...1, size: size).isEmpty)
    }

    func testNonFiniteValuesAreTreatedAsGaps() {
        let segments = SparklineGeometry.segments(values: [1, .nan, 2], range: 0...2, size: size)
        XCTAssertEqual(segments.count, 2)
    }

    func testLargerValuesAreHigherOnScreen() {
        let points = SparklineGeometry.segments(values: [0, 4], range: 0...4, size: size)[0].points
        XCTAssertEqual(points[0].y, 10, accuracy: 0.001)
        XCTAssertEqual(points[1].y, 0, accuracy: 0.001)
    }

    func testOutOfRangeValuesClampInsideBounds() {
        let points = SparklineGeometry.segments(values: [-10, 10], range: 0...4, size: size)[0].points
        XCTAssertEqual(points[0].y, 10, accuracy: 0.001)
        XCTAssertEqual(points[1].y, 0, accuracy: 0.001)
    }

    func testSingleSampleIsCenteredHorizontally() {
        let segments = SparklineGeometry.segments(values: [2], range: 0...4, size: size)
        XCTAssertEqual(segments.first?.points.first?.x ?? -1, 50, accuracy: 0.001)
    }

    func testResolvedRange() {
        XCTAssertEqual(SparklineGeometry.resolvedRange(values: [3, nil, 1, 2], explicit: nil), 1...3)
        XCTAssertEqual(SparklineGeometry.resolvedRange(values: [5, 5], explicit: nil), 4.5...5.5)
        XCTAssertEqual(SparklineGeometry.resolvedRange(values: [1, 2], explicit: 0...10), 0...10)
        XCTAssertNil(SparklineGeometry.resolvedRange(values: [nil], explicit: nil))
    }
}
