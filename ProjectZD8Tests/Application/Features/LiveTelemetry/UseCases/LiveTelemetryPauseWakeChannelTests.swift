import XCTest
@testable import ProjectZD8

/// 一時停止の起床を届ける経路が、開いている間だけ届け、閉じると終わることを検証します。
///
/// ストリームは別Taskで件数上限まで集め、終わるのを上限付きで待ちます。`close` や再度の `open` が
/// ストリームを終えなくなった場合は、待ち続けずに失敗します。
@MainActor
final class LiveTelemetryPauseWakeChannelTests: XCTestCase {
    /// 1本のストリームから集める件数の上限です。
    private static let maximumReasons = 10

    /// 開いている間に送った起床理由が順に届き、閉じるとストリームが終わります。閉じた後の送信は捨てます。
    ///
    /// 責務: 開閉と送信の基本動作を、件数上限と待機上限付きの読取で確認します。
    func testDeliversWhileOpenAndFinishesOnClose() async {
        let channel = LiveTelemetryPauseWakeChannel()
        channel.send(.deadlineReached)
        let stream = channel.open()
        channel.send(.retryDue)
        channel.send(.signal(.linkRestored))
        channel.close()
        channel.send(.signal(.foregroundEntered))

        let received = await collectUntilFinished(stream)

        XCTAssertEqual(received, [.retryDue, .signal(.linkRestored)])
    }

    /// 開き直すと前のストリームは終わり、以後の送信は新しいストリームへ届きます。
    ///
    /// 責務: 再度の `open` が前の購読を閉じることを、待機上限付きの読取で確認します。
    func testReopenFinishesPreviousStream() async {
        let channel = LiveTelemetryPauseWakeChannel()
        let first = channel.open()
        let second = channel.open()
        channel.send(.deadlineReached)
        channel.close()

        let firstReceived = await collectUntilFinished(first)
        let secondReceived = await collectUntilFinished(second)

        XCTAssertEqual(firstReceived, [])
        XCTAssertEqual(secondReceived, [.deadlineReached])
    }

    /// ストリームが終わるまで、件数と待機の上限付きで起床理由を集めます。
    ///
    /// 責務: 別Taskで最大 `maximumReasons` 件を集め、上限内に終わらなければ失敗させてTaskを取り消します。
    /// - Parameters:
    ///   - stream: 集めるストリーム。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 集めた起床理由。上限内に終わらなかった場合は `nil`。
    private func collectUntilFinished(
        _ stream: AsyncStream<LiveTelemetryPauseWakeReason>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> [LiveTelemetryPauseWakeReason]? {
        await LiveTelemetryBoundedWaiter.value("ストリームの終了", file: file, line: line) {
            var received: [LiveTelemetryPauseWakeReason] = []
            for await reason in stream {
                received.append(reason)
                if received.count >= Self.maximumReasons { break }
            }
            return received
        }
    }
}
