import Foundation
import XCTest
@testable import ProjectZD8

/// 読み込んだ軌跡から、描くルート・出す理由・注記のキーを決める規則を検証します。
///
/// 区切り・判定・文言キーは既定の実物を使います。
@MainActor
final class DrivingRouteStatusResolverTests: XCTestCase {
    /// 検証対象です。
    private let resolver = DrivingRouteStatusResolver()
    /// 未確認の復元の注記のキーです。
    private let unverifiedKey = "history.route.notice.unverified_restore"
    /// 位置情報が拒否されていた区間の注記のキーです。
    private let partialDeniedKey = "history.route.notice.partial.authorization_denied"

    /// iCloud にも無いなら、理由 notInCloud でルートはありません。
    ///
    /// 責務: `.notInCloud` が `absence.not_in_cloud` のキーと空の注記になることを確認します。
    func testNotInCloudGivesNotInCloudAbsence() {
        let status = resolver.status(for: .notInCloud)

        XCTAssertNil(status.route)
        XCTAssertEqual(status.absence?.messageKey, "history.route.absence.not_in_cloud")
        XCTAssertEqual(status.noticeKeys, [])
    }

    /// 事象だけの軌跡は、その事象の理由になります。
    ///
    /// 責務: 拒否の事象だけを持つ軌跡で、ルートが無く拒否の理由のキーになることを確認します。
    func testEventsOnlyTrackGivesEventReason() {
        let track = DrivingRouteTestValues.track(eventKinds: [.authorizationDenied])

        let status = resolver.status(for: .available(track, .recordedOnThisDevice))

        XCTAssertNil(status.route)
        XCTAssertEqual(status.absence?.messageKey, "history.route.absence.authorization_denied")
        XCTAssertEqual(status.noticeKeys, [])
    }

    /// 点のある軌跡はルートと注記を返し、理由は出しません。
    ///
    /// 責務: 途中から記録された軌跡で、全点のルートと部分の注記のキーが返ることを確認します。
    func testTrackWithPointsGivesRouteAndNotices() throws {
        let track = try partiallyRecordedTrack()

        let status = resolver.status(for: .available(track, .recordedOnThisDevice))

        XCTAssertNil(status.absence)
        XCTAssertEqual(status.route?.points.map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(status.noticeKeys, [partialDeniedKey])
    }

    /// 概略の位置だけの軌跡は、概略の区間のルートと概略の注記になります。
    ///
    /// 責務: 精度を下げた記録中の事象と精度 1,000 m の点で、区間が概略になり注記が概略だけになることを確認します。
    func testApproximateTrackGivesApproximateRouteAndNotice() throws {
        let samples = try DrivingRouteTestValues.samples(count: 4, horizontalAccuracyMeters: 1_000)
        let track = DrivingRouteTestValues.track(samples: samples, eventKinds: [.recordingWithReducedAccuracy])

        let status = resolver.status(for: .available(track, .recordedOnThisDevice))

        XCTAssertEqual(status.route?.segments.map(\.precision), [.approximate])
        XCTAssertEqual(status.noticeKeys, ["history.route.notice.reduced_accuracy"])
    }

    /// サンプルはあるが全て精度で除かれたなら、空の地図ではなく理由を出します。
    ///
    /// 責務: 精度 100 m の点だけの軌跡で、ルートが nil になり `absence.all_fixes_inaccurate` になることを確認します。
    func testTrackWithoutDrawablePointsGivesReasonInsteadOfEmptyRoute() throws {
        let samples = try DrivingRouteTestValues.samples(count: 3, horizontalAccuracyMeters: 100)
        let track = DrivingRouteTestValues.track(samples: samples, eventKinds: [.recording])

        let status = resolver.status(for: .available(track, .recordedOnThisDevice))

        XCTAssertNil(status.route)
        XCTAssertEqual(status.absence?.messageKey, "history.route.absence.all_fixes_inaccurate")
    }

    /// 精度で除いた点が 10% 以上なら、除外の注記が付きます。
    ///
    /// 責務: 10点中1点を除いた軌跡で、残りの点のルートと除外の注記のキーが返ることを確認します。
    func testExcludedPointsGiveExcludedNotice() throws {
        var samples = try DrivingRouteTestValues.samples(count: 10)
        samples[5] = try DrivingRouteTestValues.sample(index: 5, horizontalAccuracyMeters: 100)
        let track = DrivingRouteTestValues.track(samples: samples, eventKinds: [.recording])

        let status = resolver.status(for: .available(track, .recordedOnThisDevice))

        XCTAssertEqual(status.route?.points.map(\.sequence), [0, 1, 2, 3, 4, 6, 7, 8, 9])
        XCTAssertEqual(status.noticeKeys, ["history.route.notice.inaccurate_excluded"])
    }

    /// 最新か確認できなかった以前の復元なら、注記の最後に未確認を足します。
    ///
    /// 責務: `restoredEarlier(isVerifiedLatest: false)` で、部分の注記の後に未確認の注記が並ぶことを確認します。
    func testUnverifiedRestoredCopyAppendsNoticeLast() throws {
        let track = try partiallyRecordedTrack()

        let status = resolver.status(for: .available(track, .restoredEarlier(isVerifiedLatest: false)))

        XCTAssertEqual(status.route?.points.count, 5)
        XCTAssertEqual(status.noticeKeys, [partialDeniedKey, unverifiedKey])
    }

    /// 確認済みの復元・今回の取得・この端末の記録には、未確認の注記を足しません。
    ///
    /// 責務: 3つの取得元のいずれでも、注記が部分の注記だけになることを確認します。
    func testOtherSourcesDoNotAppendUnverifiedNotice() throws {
        let track = try partiallyRecordedTrack()
        let sources: [ConnectionSessionLocationTrackSource] = [
            .restoredEarlier(isVerifiedLatest: true),
            .downloadedNow,
            .recordedOnThisDevice,
        ]

        for source in sources {
            XCTAssertEqual(resolver.status(for: .available(track, source)).noticeKeys, [partialDeniedKey], "\(source)")
        }
    }

    /// 理由を出す時でも、未確認の復元なら未確認の注記を足します。
    ///
    /// 責務: 事象だけの軌跡を未確認の復元として渡した時、理由と未確認の注記の両方が返ることを確認します。
    func testUnverifiedNoticeIsAppendedEvenWithAbsence() {
        let track = DrivingRouteTestValues.track(eventKinds: [.authorizationDenied])

        let status = resolver.status(for: .available(track, .restoredEarlier(isVerifiedLatest: false)))

        XCTAssertNil(status.route)
        XCTAssertEqual(status.absence?.messageKey, "history.route.absence.authorization_denied")
        XCTAssertEqual(status.noticeKeys.last, unverifiedKey)
        XCTAssertEqual(status.noticeKeys.filter { $0 == unverifiedKey }.count, 1)
    }

    /// 拒否の後に記録中になり、5点を取得した軌跡を作ります。
    ///
    /// 責務: 途中から記録された状況の軌跡を返します。
    /// - Returns: 軌跡。
    /// - Throws: 値を作れない場合のテスト失敗。
    private func partiallyRecordedTrack() throws -> ConnectionSessionLocationTrack {
        DrivingRouteTestValues.track(
            samples: try DrivingRouteTestValues.samples(count: 5),
            eventKinds: [.authorizationDenied, .recording]
        )
    }
}
