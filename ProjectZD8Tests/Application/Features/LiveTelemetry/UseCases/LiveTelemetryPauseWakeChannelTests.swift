import XCTest
@testable import ProjectZD8

/// 一時停止の起床を届ける経路が、開いている間だけ届け、閉じると終わることを検証します。
final class LiveTelemetryPauseWakeChannelTests: XCTestCase {
    /// 開いている間に送った起床理由が順に届き、閉じるとストリームが終わります。閉じた後の送信は捨てます。
    ///
    /// 責務: 開閉と送信の基本動作を、件数上限付きの読取で確認します。
    func testDeliversWhileOpenAndFinishesOnClose() async {
        let channel = LiveTelemetryPauseWakeChannel()
        channel.send(.deadlineReached)
        let stream = channel.open()
        channel.send(.retryDue)
        channel.send(.signal(.linkRestored))
        channel.close()
        channel.send(.signal(.foregroundEntered))

        var received: [LiveTelemetryPauseWakeReason] = []
        for await reason in stream.prefix(10) { received.append(reason) }

        XCTAssertEqual(received, [.retryDue, .signal(.linkRestored)])
    }

    /// 開き直すと前のストリームは終わり、以後の送信は新しいストリームへ届きます。
    ///
    /// 責務: 再度の `open` が前の購読を閉じることを確認します。
    func testReopenFinishesPreviousStream() async {
        let channel = LiveTelemetryPauseWakeChannel()
        let first = channel.open()
        let second = channel.open()
        channel.send(.deadlineReached)
        channel.close()

        var firstReceived: [LiveTelemetryPauseWakeReason] = []
        for await reason in first.prefix(10) { firstReceived.append(reason) }
        var secondReceived: [LiveTelemetryPauseWakeReason] = []
        for await reason in second.prefix(10) { secondReceived.append(reason) }

        XCTAssertEqual(firstReceived, [])
        XCTAssertEqual(secondReceived, [.deadlineReached])
    }
}
