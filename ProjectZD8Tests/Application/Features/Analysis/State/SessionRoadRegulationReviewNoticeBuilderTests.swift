import Foundation
import XCTest
@testable import ProjectZD8

/// 照合結果の上に出す注記(車速なし・データの範囲外・指定なし)を選ぶ規則を検証します(設計書 §3.4 Notices、§7 TC1b)。
@MainActor
final class SessionRoadRegulationReviewNoticeBuilderTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues
    /// 検証対象です。
    private let builder = SessionRoadRegulationReviewNoticeBuilder()
    /// Raw の置き場所の3値です。
    private let rawLogs: [SessionRoadRegulationRawLogAvailability] = [.onDevice, .inCloud, .unreadable]

    /// 責務: 車速が無い時、Raw が iCloud にあれば speedInCloud、端末にある・読めなかった時は speedNotRecorded だけを出すことを確かめます。
    func testMissingSpeedNoticeDependsOnRawLog() {
        let review = Values.review(hasVehicleSpeed: false)
        let expected: [SessionRoadRegulationReviewNotice] = [.speedNotRecorded, .speedInCloud, .speedNotRecorded]

        for (rawLog, notice) in zip(rawLogs, expected) {
            XCTAssertEqual(builder.notices(review: review, rows: [], rawLog: rawLog), [notice], "\(rawLog)")
        }
    }

    /// 責務: 車速がある時は、Raw の置き場所に関係なく車速の注記を出さないことを確かめます。
    func testNoSpeedNoticeWhenSpeedRecorded() {
        let review = Values.review(hasVehicleSpeed: true)

        for rawLog in rawLogs {
            XCTAssertEqual(builder.notices(review: review, rows: [], rawLog: rawLog), [], "\(rawLog)")
        }
    }

    /// 責務: 範囲外の理由で判定できない行が1件でもあれば outsideData を出すことを確かめます。
    func testOutsideDataNoticeFromRowReason() {
        let rows = [
            Values.row(id: 0, kind: .speedLimit, outcome: .compliant),
            Values.row(id: 1, kind: .stop, outcome: .undeterminable, reason: .outsideRegulationData)
        ]

        XCTAssertEqual(builder.notices(review: Values.review(), rows: rows, rawLog: .onDevice), [.outsideData])
    }

    /// 責務: 版が空なら、範囲外の理由の行が無くても outsideData を出すことを確かめます。
    func testOutsideDataNoticeWhenDatasetsEmpty() {
        let rows = [Values.row(id: 0, kind: .speedLimit, outcome: .compliant)]

        XCTAssertEqual(builder.notices(review: Values.review(datasets: []), rows: rows, rawLog: .onDevice), [.outsideData])
        XCTAssertEqual(builder.notices(review: Values.review(datasets: []), rows: [], rawLog: .onDevice), [.outsideData])
    }

    /// 責務: 版があり範囲外の理由の行も無ければ、outsideData を出さないことを確かめます。
    func testNoOutsideDataNoticeWithDatasetsAndNoOutsideRow() {
        let rows = [Values.row(id: 0, kind: .speedLimit, outcome: .compliant)]

        XCTAssertEqual(builder.notices(review: Values.review(), rows: rows, rawLog: .onDevice), [])
    }

    /// 責務: 版があり、範囲外以外の理由(trackGap など)で判定できない行だけなら outsideData を出さないことを確かめます。
    func testOtherUndeterminedReasonsDoNotTriggerOutsideData() {
        let rows = [
            Values.row(id: 0, kind: .stop, outcome: .undeterminable, reason: .trackGap),
            Values.row(id: 1, kind: .oneWay, outcome: .undeterminable, reason: .headingUnknown)
        ]

        XCTAssertEqual(builder.notices(review: Values.review(), rows: rows, rawLog: .onDevice), [])
    }

    /// 責務: 指定なしの行が1件でもあれば unregulatedExplained を出すことを確かめます。
    func testUnregulatedNoticeFromRows() {
        let rows = [
            Values.row(id: 0, kind: .speedLimit, outcome: .unregulated),
            Values.row(id: 1, kind: .speedLimit, outcome: .compliant)
        ]

        XCTAssertEqual(builder.notices(review: Values.review(), rows: rows, rawLog: .onDevice), [.unregulatedExplained])
    }

    /// 責務: 指定なしの行が無く、他の条件にも当たらなければ注記は空であることを確かめます。
    func testNoNoticesWithoutAnyCondition() {
        let rows = [Values.row(id: 0, kind: .speedLimit, outcome: .possibleIssue)]

        XCTAssertEqual(builder.notices(review: Values.review(), rows: rows, rawLog: .inCloud), [])
    }

    /// 責務: 3つの条件すべてに当たる時、車速 → 範囲外 → 指定なしの順に並べることを確かめます(行の並びは逆にする)。
    func testAllNoticesAreOrdered() {
        let rows = [
            Values.row(id: 0, kind: .speedLimit, outcome: .unregulated),
            Values.row(id: 1, kind: .oneWay, outcome: .undeterminable, reason: .outsideRegulationData)
        ]
        let review = Values.review(hasVehicleSpeed: false)

        XCTAssertEqual(builder.notices(review: review, rows: rows, rawLog: .inCloud), [.speedInCloud, .outsideData, .unregulatedExplained])
        XCTAssertEqual(builder.notices(review: review, rows: rows, rawLog: .unreadable), [.speedNotRecorded, .outsideData, .unregulatedExplained])
    }
}
