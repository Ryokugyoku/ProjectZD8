import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの理由と注記の判定(設計書 §3.2 の規則1〜5と理由の優先度)を検証します。
@MainActor
final class DrivingRouteAssessorTests: XCTestCase {
    /// 検証対象です(既定の除外の割合 0.1)。
    private let assessor = DrivingRouteAssessor()

    /// 記録中以外の事象の種類と、対応する理由です(優先度の高い順)。
    private let prioritizedReasons: [(ConnectionSessionLocationEventKind, DrivingRouteAbsenceReason)] = [
        (.unsupportedPlatform, .unsupportedPlatform),
        (.disabledBySetting, .disabledBySetting),
        (.authorizationRestricted, .authorizationRestricted),
        (.authorizationDenied, .authorizationDenied),
        (.authorizationNotDetermined, .authorizationNotDetermined),
        (.backgroundWithoutAlwaysAuthorization, .backgroundWithoutAlwaysAuthorization),
        (.locationUnavailable, .locationUnavailable),
    ]

    /// 点があり記録中の事象だけなら、理由も注記もありません。
    ///
    /// 責務: 規則1で、事象・概略・除外のどれにも当たらない時に注記が空になることを確認します。
    func testRouteWithOnlyRecordingEventHasNoReasonAndNoNotices() throws {
        let assessment = try assessRoute(eventKinds: [.recording])

        XCTAssertEqual(assessment, DrivingRouteAssessment(absenceReason: nil, notices: []))
    }

    /// 途中から記録された(最初は理由あり、後で記録中)なら、ルートを出し、部分の注記を付けます。
    ///
    /// 責務: 規則1で理由を出さず、`partiallyRecorded(最初の事象の理由)` の注記だけになることを確認します。
    func testRecordingAfterReasonEventGivesPartialNotice() throws {
        let assessment = try assessRoute(eventKinds: [.authorizationNotDetermined, .recording])

        XCTAssertNil(assessment.absenceReason)
        XCTAssertEqual(assessment.notices, [.partiallyRecorded(.authorizationNotDetermined)])
    }

    /// 部分の注記の理由は、事象の順序によらず優先度の最も高いものです。
    ///
    /// 責務: 7種の全ての組について、両方の順序で優先度の高い方が選ばれることを確認します。
    func testPartialNoticePicksHighestPriorityReasonForEveryPair() throws {
        for (higherIndex, lowerIndex) in prioritizedPairs() {
            let higher = prioritizedReasons[higherIndex]
            let lower = prioritizedReasons[lowerIndex]
            for kinds in [[higher.0, lower.0, .recording], [lower.0, higher.0, .recording]] {
                let assessment = try assessRoute(eventKinds: kinds)
                XCTAssertEqual(assessment.notices, [.partiallyRecorded(higher.1)], "\(kinds)")
            }
        }
    }

    /// 精度を下げた記録中の事象があれば、区間が正確でも概略の注記が付きます。
    ///
    /// 責務: `recordingWithReducedAccuracy` の事象だけから `reducedAccuracy` が出ることを確認します。
    func testReducedAccuracyEventGivesReducedAccuracyNotice() throws {
        let assessment = try assessRoute(eventKinds: [.recording, .recordingWithReducedAccuracy])

        XCTAssertEqual(assessment, DrivingRouteAssessment(absenceReason: nil, notices: [.reducedAccuracy]))
    }

    /// 概略の区間があれば、事象が記録中だけでも概略の注記が付きます。
    ///
    /// 責務: 区間の精度 `approximate` だけから `reducedAccuracy` が出ることを確認します。
    func testApproximateSegmentGivesReducedAccuracyNotice() throws {
        let assessment = try assessRoute(eventKinds: [.recording], precision: .approximate)

        XCTAssertEqual(assessment, DrivingRouteAssessment(absenceReason: nil, notices: [.reducedAccuracy]))
    }

    /// 概略の位置だけで記録したセッションは、概略の注記だけになります。
    ///
    /// 責務: 事象が精度を下げた記録中だけで区間も概略の時、注記が `reducedAccuracy` 1つで部分の注記が無いことを確認します。
    func testApproximateOnlySessionHasOnlyReducedAccuracyNotice() throws {
        let assessment = try assessRoute(eventKinds: [.recordingWithReducedAccuracy], precision: .approximate)

        XCTAssertEqual(assessment, DrivingRouteAssessment(absenceReason: nil, notices: [.reducedAccuracy]))
    }

    /// 除外の割合がちょうど 10% なら除外の注記が付きます。
    ///
    /// 責務: 全10点中1点を除いた(0.1 ちょうど)時に `inaccurateFixesExcluded` が出ることを確認します。
    func testExcludedRatioExactlyTenPercentGivesNotice() throws {
        let assessment = try assessRoute(eventKinds: [.recording], sampleCount: 10, excludedFixCount: 1)

        XCTAssertEqual(assessment.notices, [.inaccurateFixesExcluded])
    }

    /// 除外の割合が 10% 未満なら除外の注記は付きません。
    ///
    /// 責務: 全1000点中99点を除いた(0.099)時に注記が出ないことを確認します。
    func testExcludedRatioBelowTenPercentGivesNoNotice() throws {
        let assessment = try assessRoute(eventKinds: [.recording], sampleCount: 1_000, excludedFixCount: 99)

        XCTAssertEqual(assessment.notices, [])
    }

    /// 除外の注記のしきい値は初期化子で変えられます。
    ///
    /// 責務: しきい値 0.5 では 0.3 で出ず、0.5 ちょうどで出ることを確認します。
    func testCustomExcludedNoticeRatioIsUsed() throws {
        let custom = DrivingRouteAssessor(excludedNoticeRatio: 0.5)

        let below = try assessRoute(eventKinds: [.recording], sampleCount: 10, excludedFixCount: 3, assessor: custom)
        let atRatio = try assessRoute(eventKinds: [.recording], sampleCount: 10, excludedFixCount: 5, assessor: custom)

        XCTAssertEqual(below.notices, [])
        XCTAssertEqual(atRatio.notices, [.inaccurateFixesExcluded])
    }

    /// 全点数が 0 の時は、除外の注記を出しません。
    ///
    /// 責務: 点のあるルートの全点数・除外数がともに 0 の時、割合を計算できないため除外の注記が出ないことを確認します。
    func testZeroTotalFixCountGivesNoExcludedNotice() throws {
        let track = DrivingRouteTestValues.track(samples: try DrivingRouteTestValues.samples(count: 3), eventKinds: [.recording])
        let route = DrivingRouteTestValues.route([try DrivingRouteTestValues.segment(0..<3)], totalFixCount: 0, excludedFixCount: 0)

        XCTAssertEqual(assessor.assess(track: track, route: route), DrivingRouteAssessment(absenceReason: nil, notices: []))
    }

    /// 注記は「部分 → 概略 → 除外」の順に並びます。
    ///
    /// 責務: 3つの注記が同時に出る時の順序を、事象の順序を変えても確認します。
    func testNoticesAreOrderedPartialReducedExcluded() throws {
        let expected: [DrivingRouteNotice] = [.partiallyRecorded(.authorizationDenied), .reducedAccuracy, .inaccurateFixesExcluded]
        for kinds in [
            [ConnectionSessionLocationEventKind.authorizationDenied, .recordingWithReducedAccuracy],
            [.recordingWithReducedAccuracy, .authorizationDenied],
        ] {
            let assessment = try assessRoute(eventKinds: kinds, sampleCount: 10, excludedFixCount: 5)
            XCTAssertEqual(assessment, DrivingRouteAssessment(absenceReason: nil, notices: expected), "\(kinds)")
        }
    }

    /// 点が無くサンプルがある(すべて除外)なら、事象の理由より先に精度の理由になります。
    ///
    /// 責務: 規則2が規則3より先に適用され、事象の有無によらず `allFixesInaccurate` になることを確認します。
    func testAllSamplesExcludedIsAllFixesInaccurate() throws {
        let eventKindLists: [[ConnectionSessionLocationEventKind]] = [[], [.recording], [.authorizationDenied]]
        for kinds in eventKindLists {
            let track = DrivingRouteTestValues.track(samples: try DrivingRouteTestValues.samples(count: 3), eventKinds: kinds)
            let route = DrivingRouteTestValues.route([], totalFixCount: 3, excludedFixCount: 3)

            XCTAssertEqual(assessor.assess(track: track, route: route).absenceReason, .allFixesInaccurate, "\(kinds)")
        }
    }

    /// 点もサンプルも無く、記録中以外の事象が1種類なら、その理由になります。
    ///
    /// 責務: 規則3で、7種の事象それぞれが対応する理由になることを確認します。
    func testSingleReasonEventWithoutSamplesGivesItsReason() {
        for (kind, reason) in prioritizedReasons {
            let assessment = assessEmptyRoute(eventKinds: [kind])
            XCTAssertEqual(assessment.absenceReason, reason, "\(kind)")
        }
    }

    /// 点もサンプルも無く事象が複数なら、順序によらず優先度の最も高い理由になります。
    ///
    /// 責務: 規則3で、7種の全ての組について両方の順序と記録中の事象の混在を確認します。
    func testReasonPicksHighestPriorityForEveryPair() {
        for (higherIndex, lowerIndex) in prioritizedPairs() {
            let higher = prioritizedReasons[higherIndex]
            let lower = prioritizedReasons[lowerIndex]
            for kinds in [[higher.0, lower.0], [lower.0, .recording, higher.0]] {
                XCTAssertEqual(assessEmptyRoute(eventKinds: kinds).absenceReason, higher.1, "\(kinds)")
            }
        }
    }

    /// 記録中の事象しか無く点もサンプルも無ければ、位置を1件も取得できなかった理由になります。
    ///
    /// 責務: 規則4で、記録中と精度を下げた記録中のどちらでも `noFixesReceived` になることを確認します。
    func testOnlyRecordingEventsWithoutSamplesIsNoFixesReceived() {
        for kinds in [
            [ConnectionSessionLocationEventKind.recording],
            [.recordingWithReducedAccuracy],
            [.recording, .recordingWithReducedAccuracy],
        ] {
            XCTAssertEqual(assessEmptyRoute(eventKinds: kinds).absenceReason, .noFixesReceived, "\(kinds)")
        }
    }

    /// 事象もサンプルも無ければ、記録が無い理由になります。
    ///
    /// 責務: 規則5で `notRecorded` になることを確認します。
    func testNothingRecordedIsNotRecorded() {
        XCTAssertEqual(assessEmptyRoute(eventKinds: []).absenceReason, .notRecorded)
    }

    /// 点のある軌跡を判定します。
    ///
    /// 責務: 指定件数のサンプルと事象を持つ軌跡と、同じ件数の点を1区間に持つルートを作って判定します。
    /// - Parameters:
    ///   - eventKinds: 起きた順の事象の種類。
    ///   - precision: 区間の精度の段階。
    ///   - sampleCount: サンプルの件数(区間の点は除いた数を引いた件数)。
    ///   - excludedFixCount: 除いた数。
    ///   - assessor: 判定に使う型。省くと既定の判定。
    /// - Returns: 判定の結果。
    /// - Throws: 値を作れない場合のテスト失敗。
    private func assessRoute(
        eventKinds: [ConnectionSessionLocationEventKind],
        precision: DrivingRoutePrecision = .precise,
        sampleCount: Int = 5,
        excludedFixCount: Int = 0,
        assessor: DrivingRouteAssessor? = nil
    ) throws -> DrivingRouteAssessment {
        let track = DrivingRouteTestValues.track(samples: try DrivingRouteTestValues.samples(count: sampleCount), eventKinds: eventKinds)
        let segment = try DrivingRouteTestValues.segment(0..<(sampleCount - excludedFixCount), precision: precision)
        let route = DrivingRouteTestValues.route([segment], totalFixCount: sampleCount, excludedFixCount: excludedFixCount)
        return (assessor ?? self.assessor).assess(track: track, route: route)
    }

    /// 点もサンプルも無い軌跡を判定します。
    ///
    /// 責務: 事象だけを持つ軌跡と空のルートを判定します。
    /// - Parameter eventKinds: 起きた順の事象の種類。
    /// - Returns: 判定の結果。
    private func assessEmptyRoute(eventKinds: [ConnectionSessionLocationEventKind]) -> DrivingRouteAssessment {
        let track = DrivingRouteTestValues.track(eventKinds: eventKinds)
        return assessor.assess(track: track, route: DrivingRouteTestValues.route([], totalFixCount: 0))
    }

    /// 優先度の表の全ての組を返します。
    ///
    /// 責務: (高い方の位置, 低い方の位置) の組を、重複なく全て返します。
    /// - Returns: 21組。
    private func prioritizedPairs() -> [(Int, Int)] {
        let indices = prioritizedReasons.indices
        return indices.flatMap { higher in indices.filter { $0 > higher }.map { (higher, $0) } }
    }
}
