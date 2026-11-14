import Foundation
import XCTest
@testable import ProjectZD8

/// 1世代の記録状態が、manifest位置・単調時刻・commit経過・欠損番号を仕様どおりに扱うことを検証します。
final class AcquisitionRecordingSessionTests: XCTestCase {
    /// 要求順をmanifest位置へ対応付け、重複した要求は最初の位置を使います。
    ///
    /// 責務: manifest位置の対応表と区間の値の保持を確認します。
    func testManifestOrdinalsUseFirstPosition() {
        let session = makeSession(requests: [0x0C, 0x0D, 0x0C])

        XCTAssertEqual(session.manifestOrdinalByRequest, [request(0x0C): 0, request(0x0D): 1])
        XCTAssertEqual(session.segmentOrdinal, 2)
        XCTAssertEqual(session.segmentFirstSequence, 40)
    }

    /// 単調時刻の刻印は、前回より大きければそのまま、等しいか小さければ前回値に揃えます。
    ///
    /// 責務: 起点・増加・同値・逆行の各読取の刻印値を確認します。
    func testStampNeverDecreases() {
        var session = makeSession(anchor: 1_000)

        XCTAssertEqual(session.stamp(900), 1_000)
        XCTAssertEqual(session.stamp(1_500), 1_500)
        XCTAssertEqual(session.stamp(1_500), 1_500)
        XCTAssertEqual(session.stamp(1_200), 1_500)
        XCTAssertEqual(session.lastStampedNanoseconds, 1_500)
    }

    /// commit経過は前回の試行から測り、前回より前の読取は0です。commit試行の記録は戻りません。
    ///
    /// 責務: 経過の計算、逆行時の0、試行時刻の更新と逆行の無視を確認します。
    func testElapsedSinceLastCommitAttempt() {
        var session = makeSession(anchor: 1_000)

        XCTAssertEqual(session.elapsedSinceLastCommit(at: 1_250), 250)
        XCTAssertEqual(session.elapsedSinceLastCommit(at: 1_000), 0)
        XCTAssertEqual(session.elapsedSinceLastCommit(at: 999), 0)
        session.markCommitAttempt(at: 2_000)
        XCTAssertEqual(session.elapsedSinceLastCommit(at: 2_100), 100)
        session.markCommitAttempt(at: 1_500)
        XCTAssertEqual(session.lastCommitAttemptNanoseconds, 2_000)
    }

    /// 欠損番号は初期値から1ずつ払い出します。
    ///
    /// 責務: 欠損番号の払い出しと次の値を確認します。
    func testTakeGapOrdinalIncrements() {
        var session = makeSession(nextGapOrdinal: 3)

        XCTAssertEqual(session.takeGapOrdinal(), 3)
        XCTAssertEqual(session.takeGapOrdinal(), 4)
        XCTAssertEqual(session.nextGapOrdinal, 5)
    }

    /// 生成直後の区間は開いていて、区間の開始日時を保持します。
    ///
    /// 責務: 区間の初期状態を確認します。
    func testInitialSegmentIsOpen() {
        let session = makeSession()

        XCTAssertTrue(session.isSegmentOpen)
        XCTAssertEqual(session.segmentStartedAt, Date(timeIntervalSince1970: 7))
    }

    /// 保存するbatch番号は、起点にループのbatch番号を足した値です。
    ///
    /// 責務: 起点0とプロセス復帰後の起点での変換を確認します。
    func testStoredBatchOrdinalAddsBase() {
        XCTAssertEqual(makeSession().storedBatchOrdinal(3), 3)
        XCTAssertEqual(makeSession(batchOrdinalBase: 12).storedBatchOrdinal(0), 12)
        XCTAssertEqual(makeSession(batchOrdinalBase: 12).storedBatchOrdinal(4), 16)
    }

    /// 区間を閉じて次の区間を開くと、番号・最初の連番・開始日時が置き換わり、単調時刻とcommit経過の起点が新しい区間の起点になります。
    ///
    /// 責務: `closeSegment` と `openSegment` の状態遷移と、前の区間より小さい起点での刻印を確認します。
    func testCloseAndOpenSegmentResetsBaselines() {
        var session = makeSession(anchor: 9_000)
        _ = session.stamp(9_500)
        session.closeSegment()
        XCTAssertFalse(session.isSegmentOpen)

        session.openSegment(ordinal: 3, firstSequence: 55, startedAt: Date(timeIntervalSince1970: 20), anchorNanoseconds: 4_000)

        XCTAssertTrue(session.isSegmentOpen)
        XCTAssertEqual(session.segmentOrdinal, 3)
        XCTAssertEqual(session.segmentFirstSequence, 55)
        XCTAssertEqual(session.segmentStartedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(session.stamp(4_100), 4_100)
        XCTAssertEqual(session.elapsedSinceLastCommit(at: 4_200), 200)
    }

    /// テスト用の記録状態を生成します。
    ///
    /// 責務: 要求列・起点・欠損番号だけを差し替えた記録状態を返します。
    /// - Parameters:
    ///   - requests: manifest順の Service 01 PID。
    ///   - anchor: 単調時計の起点。
    ///   - nextGapOrdinal: 次の欠損番号。
    ///   - batchOrdinalBase: 保存するbatch番号の起点。
    /// - Returns: 記録状態。
    private func makeSession(
        requests: [UInt8] = [0x0C],
        anchor: UInt64 = 0,
        nextGapOrdinal: Int = 0,
        batchOrdinalBase: Int64 = 0
    ) -> AcquisitionRecordingSession {
        AcquisitionRecordingSession(
            sessionID: ConnectionSessionID(), generation: 1, orderedRequests: requests.map(request),
            segmentOrdinal: 2, segmentFirstSequence: 40, segmentStartedAt: Date(timeIntervalSince1970: 7),
            nextGapOrdinal: nextGapOrdinal, anchorNanoseconds: anchor, batchOrdinalBase: batchOrdinalBase
        )
    }

    /// Service 01 の要求を生成します。
    ///
    /// 責務: PID番号を要求へ変換します。
    /// - Parameter pid: PID番号。
    /// - Returns: 要求。
    private func request(_ pid: UInt8) -> OBDPIDRequest {
        OBDPIDRequest(service: 0x01, pid: pid)
    }
}
