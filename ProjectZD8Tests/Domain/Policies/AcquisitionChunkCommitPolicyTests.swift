import XCTest
@testable import ProjectZD8

/// チャンクcommit判定の件数・経過の境界を検証します。
final class AcquisitionChunkCommitPolicyTests: XCTestCase {
    /// 判定対象のPolicyです。
    private let policy = AcquisitionChunkCommitPolicy()
    /// 件数の上限です。
    private let countLimit = AcquisitionChunkCommitPolicy.bufferedCountLimit
    /// 経過の上限です。
    private let elapsedLimit = AcquisitionChunkCommitPolicy.elapsedLimitNanoseconds

    /// 上限値が判定に意味を持つ範囲であることを確認します。
    ///
    /// 責務: 件数上限が2以上、経過上限が0より大きいことを確認します。
    func testLimitsAreMeaningful() {
        XCTAssertGreaterThan(countLimit, 1)
        XCTAssertGreaterThan(elapsedLimit, 0)
    }

    /// バッファ0件は経過が上限を超えても保留します。
    ///
    /// 責務: 空バッファが常にcommitされないことを確認します。
    func testEmptyBufferNeverCommits() {
        XCTAssertFalse(policy.shouldCommit(bufferedCount: 0, elapsedSinceLastCommitNanoseconds: 0))
        XCTAssertFalse(policy.shouldCommit(bufferedCount: 0, elapsedSinceLastCommitNanoseconds: elapsedLimit))
        XCTAssertFalse(policy.shouldCommit(bufferedCount: 0, elapsedSinceLastCommitNanoseconds: elapsedLimit + 1))
    }

    /// 件数が上限未満・ちょうど・超過の境界で判定します。
    ///
    /// 責務: 経過が短い時、件数上限以上だけがcommitになることを確認します。
    func testCountBoundary() {
        XCTAssertFalse(policy.shouldCommit(bufferedCount: countLimit - 1, elapsedSinceLastCommitNanoseconds: 0))
        XCTAssertTrue(policy.shouldCommit(bufferedCount: countLimit, elapsedSinceLastCommitNanoseconds: 0))
        XCTAssertTrue(policy.shouldCommit(bufferedCount: countLimit + 1, elapsedSinceLastCommitNanoseconds: 0))
    }

    /// 経過が上限未満・ちょうど・超過の境界で判定します。
    ///
    /// 責務: 件数が少ない時、経過上限以上だけがcommitになることを確認します。
    func testElapsedBoundary() {
        XCTAssertFalse(policy.shouldCommit(bufferedCount: 1, elapsedSinceLastCommitNanoseconds: elapsedLimit - 1))
        XCTAssertTrue(policy.shouldCommit(bufferedCount: 1, elapsedSinceLastCommitNanoseconds: elapsedLimit))
        XCTAssertTrue(policy.shouldCommit(bufferedCount: 1, elapsedSinceLastCommitNanoseconds: elapsedLimit + 1))
    }

    /// 件数・経過がともに上限以上ならcommitします。
    ///
    /// 責務: 両条件が成立してもcommitになることを確認します。
    func testBothAtLimitCommits() {
        XCTAssertTrue(policy.shouldCommit(bufferedCount: countLimit, elapsedSinceLastCommitNanoseconds: elapsedLimit))
    }

    /// 件数・経過がともに上限未満ならcommitしません。
    ///
    /// 責務: 両条件が不成立なら保留になることを確認します。
    func testBothBelowLimitDoesNotCommit() {
        XCTAssertFalse(policy.shouldCommit(bufferedCount: countLimit - 1, elapsedSinceLastCommitNanoseconds: elapsedLimit - 1))
    }
}
