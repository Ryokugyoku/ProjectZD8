import XCTest
@testable import ProjectZD8

/// 後勝ちの競合解決を確認します。
final class SyncConflictResolverTests: XCTestCase {
    private let resolver = SyncConflictResolver()

    /// 責務: ローカル行が無い、または未送信の変更が無ければリモートを適用することを確認します。
    func testAppliesRemoteWhenLocalMissingOrClean() {
        XCTAssertEqual(resolver.resolve(localModifiedAt: nil, localIsPending: false, remoteModifiedAt: 1), .applyRemote)
        XCTAssertEqual(resolver.resolve(localModifiedAt: 10, localIsPending: false, remoteModifiedAt: 1), .applyRemote)
    }

    /// 責務: 未送信の変更がある時は更新日時が新しい方を残すことを確認します(同時刻はローカル)。
    func testPendingLocalComparesModifiedAt() {
        XCTAssertEqual(resolver.resolve(localModifiedAt: 10, localIsPending: true, remoteModifiedAt: 11), .applyRemote)
        XCTAssertEqual(resolver.resolve(localModifiedAt: 10, localIsPending: true, remoteModifiedAt: 9), .keepLocal)
        XCTAssertEqual(resolver.resolve(localModifiedAt: 10, localIsPending: true, remoteModifiedAt: 10), .keepLocal)
    }
}
