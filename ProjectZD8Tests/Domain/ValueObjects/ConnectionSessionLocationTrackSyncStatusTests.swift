import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationTrackSyncStatus.needsUpload` の真偽表を検証します。
final class ConnectionSessionLocationTrackSyncStatusTests: XCTestCase {
    /// 未送信と送信後に変化した状態だけが、送信が必要です。
    ///
    /// 責務: 5つの状態すべての `needsUpload` を期待値の表と照合します。
    func testNeedsUploadTruthTable() {
        let table: [(ConnectionSessionLocationTrackSyncStatus, Bool)] = [
            (.nothingToSync, false),
            (.notUploaded, true),
            (.uploaded(manifestDigest: "d"), false),
            (.changedSinceUpload(previousDigest: "d"), true),
            (.restoredFromCloud(manifestDigest: "d"), false)
        ]

        for (status, expected) in table {
            XCTAssertEqual(status.needsUpload, expected, "\(status)")
        }
    }
}
