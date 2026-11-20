import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationTrackSyncStatusPolicy` の判定(上から順に適用)を仕様から検証します。
final class ConnectionSessionLocationTrackSyncStatusPolicyTests: XCTestCase {
    /// 値生成の別名です。
    private typealias Values = ConnectionSessionLocationTrackValueFixtures

    /// 比較の基準にする水位です(サンプル3件・最終2、事象2件・最終1)。
    /// 比較の基準にする水位の説明は下記のとおりです。
    private let base = Values.watermark(3, 2, 2, 1)
    /// 検証対象のポリシーです。
    private let policy = ConnectionSessionLocationTrackSyncStatusPolicy()

    /// 同期記録を作ります。
    ///
    /// 責務: 由来と水位を指定した、固定ダイジェストの同期記録を返します。
    /// - Parameters:
    ///   - origin: 由来。
    ///   - watermark: 記録の水位。
    ///   - digest: ダイジェスト。
    /// - Returns: 同期記録。
    private func record(
        _ origin: ConnectionSessionLocationTrackSyncOrigin,
        watermark: ConnectionSessionLocationTrackWatermark,
        digest: String = Values.digest("c")
    ) -> ConnectionSessionLocationTrackSyncRecord {
        Values.syncRecord(ConnectionSessionID(), origin: origin, digest: digest, watermark: watermark)
    }

    /// 記録なしでローカルが空なら送るものがありません。
    ///
    /// 責務: 記録なし・空の水位の判定が `nothingToSync` であることを確認します。
    func testNoRecordAndEmptyLocalIsNothingToSync() {
        XCTAssertEqual(policy.status(localWatermark: .empty, record: nil), .nothingToSync)
    }

    /// 記録なしでサンプルがあれば未送信です。
    ///
    /// 責務: サンプルだけがある場合の `notUploaded` を確認します。
    func testNoRecordWithSamplesIsNotUploaded() {
        let status = policy.status(localWatermark: Values.watermark(1, 0, 0, nil), record: nil)

        XCTAssertEqual(status, .notUploaded)
    }

    /// 記録なしで事象だけでも未送信です。
    ///
    /// 責務: 事象だけがある場合も `notUploaded` になる(位置が取れなかった理由も送る)ことを確認します。
    func testNoRecordWithEventsOnlyIsNotUploaded() {
        let status = policy.status(localWatermark: Values.watermark(0, nil, 1, 0), record: nil)

        XCTAssertEqual(status, .notUploaded)
    }

    /// uploaded の記録と水位が同じなら送信済みで、ダイジェストを持ちます。
    ///
    /// 責務: 水位が完全一致する時の `uploaded(manifestDigest:)` を確認します。
    func testUploadedWithSameWatermarkIsUploaded() {
        let stored = record(.uploaded, watermark: base)

        let status = policy.status(localWatermark: base, record: stored)

        XCTAssertEqual(status, .uploaded(manifestDigest: Values.digest("c")))
    }

    /// サンプル件数だけが違えば送信後に変化しています。
    ///
    /// 責務: サンプル件数の違いだけで `changedSinceUpload` になり、前回のダイジェストを持つことを確認します。
    func testSampleCountDifferenceIsChanged() {
        let local = Values.watermark(4, 2, 2, 1)

        assertChanged(local: local)
    }

    /// 最終 sequence だけが違えば送信後に変化しています。
    ///
    /// 責務: 最終 sequence の違いだけで `changedSinceUpload` になることを確認します。
    func testLastSampleSequenceDifferenceIsChanged() {
        let local = Values.watermark(3, 3, 2, 1)

        assertChanged(local: local)
    }

    /// 事象件数だけが違えば送信後に変化しています。
    ///
    /// 責務: 事象件数の違いだけで `changedSinceUpload` になることを確認します。
    func testEventCountDifferenceIsChanged() {
        let local = Values.watermark(3, 2, 3, 1)

        assertChanged(local: local)
    }

    /// 最終 ordinal だけが違えば送信後に変化しています。
    ///
    /// 責務: 最終 ordinal の違いだけで `changedSinceUpload` になることを確認します。
    func testLastEventOrdinalDifferenceIsChanged() {
        let local = Values.watermark(3, 2, 2, 2)

        assertChanged(local: local)
    }

    /// 復元した記録なら、水位が違っても復元済みです。
    ///
    /// 責務: restored は水位の比較より優先され、`restoredFromCloud` になることを確認します。
    func testRestoredRecordIsRestoredEvenWhenWatermarkDiffers() {
        let stored = record(.restored, watermark: base)
        let local = Values.watermark(9, 8, 7, 6)

        XCTAssertEqual(policy.status(localWatermark: local, record: stored), .restoredFromCloud(manifestDigest: Values.digest("c")))
        XCTAssertEqual(policy.status(localWatermark: base, record: stored), .restoredFromCloud(manifestDigest: Values.digest("c")))
    }

    /// 復元した記録は、ローカルが空でも復元済みです(判定の順序)。
    ///
    /// 責務: restored の判定が「ローカルが空」の判定より先であることを確認します。
    func testRestoredRecordWinsOverEmptyLocal() {
        let stored = record(.restored, watermark: base)

        XCTAssertEqual(policy.status(localWatermark: .empty, record: stored), .restoredFromCloud(manifestDigest: Values.digest("c")))
    }

    /// ローカルが空で uploaded の記録があれば、送るものはありません。
    ///
    /// 責務: 空のローカルが水位の比較より優先され `nothingToSync` になることを確認します。
    func testEmptyLocalWithUploadedRecordIsNothingToSync() {
        let stored = record(.uploaded, watermark: base)

        XCTAssertEqual(policy.status(localWatermark: .empty, record: stored), .nothingToSync)
    }

    /// 水位が違う uploaded の記録が `changedSinceUpload` になることを確認します。
    ///
    /// 責務: 記録の水位を `base`、ローカルを `local` として判定し、前回のダイジェストが引き継がれることを検証します。
    /// - Parameter local: ローカルの水位。
    private func assertChanged(
        local: ConnectionSessionLocationTrackWatermark,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let stored = record(.uploaded, watermark: base)

        let status = policy.status(localWatermark: local, record: stored)

        XCTAssertEqual(status, .changedSinceUpload(previousDigest: Values.digest("c")), file: file, line: line)
    }
}
