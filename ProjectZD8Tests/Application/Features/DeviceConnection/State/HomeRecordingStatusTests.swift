import XCTest
@testable import ProjectZD8

/// ホームの記録状態の文言キーと値の等価性を検証します。
@MainActor
final class HomeRecordingStatusTests: XCTestCase {
    /// 記録中・経過時間・記録していないの文言キーは設計どおりです。
    ///
    /// 責務: 3つのキー定数を確かめます。
    func testKeys() {
        XCTAssertEqual(HomeRecordingStatus.activeKey, "home.recording.active")
        XCTAssertEqual(HomeRecordingStatus.elapsedKey, "home.recording.elapsed")
        XCTAssertEqual(HomeRecordingStatus.notRecordingKey, "home.recording.not_recording")
    }

    /// 記録中は開始時刻まで一致した時だけ等しく、記録していない状態とは等しくありません。
    ///
    /// 責務: 開始時刻を経過時間の起点として区別できることを確かめます。
    func testRecordingDistinguishesStartedAt() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(HomeRecordingStatus.recording(startedAt: start), .recording(startedAt: start))
        XCTAssertNotEqual(HomeRecordingStatus.recording(startedAt: start), .recording(startedAt: start.addingTimeInterval(1)))
        XCTAssertNotEqual(HomeRecordingStatus.recording(startedAt: start), .notRecording)
    }
}
