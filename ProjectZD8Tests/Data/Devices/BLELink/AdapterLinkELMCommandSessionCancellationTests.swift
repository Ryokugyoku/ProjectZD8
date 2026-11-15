import Foundation
import XCTest
@testable import ProjectZD8

/// 取り消された車両確認・初期化が、取り消し後に次のコマンドを送らず、受信の利用権をすぐ手放すことを検証します
/// (`AdapterLinkELMCommandSession` を通る `AdapterLinkVehicleResponseConfirmer` と `AdapterLinkELMInitializer`)。
@MainActor
final class AdapterLinkELMCommandSessionCancellationTests: XCTestCase {
    /// 取り消し時のリンク fake です。
    private var link: CancellingAdapterLinkFake!

    /// 検証に使うバイトストリームです。
    private var stream: AdapterLinkByteStream!

    /// 初期化・車両確認に応答するリンクとストリームを作ります。
    ///
    /// 責務: 全コマンドに応答する台本と、指定の時間倍率で待つストリームを組み立てます。
    /// - Parameter timeScale: 待ち時間を縮める倍率。1 なら実時間、`nil` なら既定の倍率です。
    private func makeStream(timeScale requestedTimeScale: Int64? = nil) {
        let timeScale = requestedTimeScale ?? AdapterLinkByteStreamHarness.defaultTimeScale
        link = CancellingAdapterLinkFake()
        link.replies = AdapterLinkELMReplyFixtures.initializableAdapter(
            stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        stream = AdapterLinkByteStream(link: link) { duration in try await Task.sleep(for: duration / timeScale) }
    }

    /// 結果が取り消しであることを確認します。
    ///
    /// 責務: 上限内に終わり、`CancellationError` で失敗したことを検証します。
    /// - Parameter outcome: 上限付きで待った結果。
    private func assertCancelled<Value>(_ outcome: Result<Value, any Error>?, file: StaticString = #filePath, line: UInt = #line) {
        guard let outcome else { return }
        switch outcome {
        case let .success(value):
            XCTFail("取り消されずに成功しました: \(value)", file: file, line: line)
        case let .failure(error):
            XCTAssertTrue(error is CancellationError, "実際のエラー: \(error)", file: file, line: line)
        }
    }

    /// 受信の利用権を別の利用者がすぐ取れることを確認します。
    ///
    /// 責務: 取り消しの直後に利用権を上限付きで取得し、すぐ返します。
    private func assertLeaseIsAvailable(file: StaticString = #filePath, line: UInt = #line) async {
        let stream: AdapterLinkByteStream = self.stream
        let outcome = await AdapterLinkBoundedAwait.run("利用権の取得", file: file, line: line) {
            let lease = try await stream.acquireLease()
            stream.release(lease)
            return true
        }
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome, file: file, line: line), true, file: file, line: line)
    }

    /// 車両確認のタイムアウト設定の書き込み中に取り消されたら、`0100` を送りません。
    ///
    /// 責務: 応答は受信済みでも取り消し後に次のコマンドを送らず、取り消しで終わり、利用権がすぐ空くことを確認します。
    func testCancelledConfirmationDoesNotSendRequestAfterCancellation() async {
        makeStream()
        link.cancellingCommand = "ATSTFF"
        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: stream)

        let outcome = await AdapterLinkBoundedAwait.run("取り消された車両確認") {
            try await confirmer.confirmVehicleResponse(timeout: .adapterMaximum)
        }

        assertCancelled(outcome)
        XCTAssertEqual(link.writtenCommands, ["ATSTFF"])
        await assertLeaseIsAvailable()
    }

    /// 初期化のリセットの書き込み中に取り消されたら、以降の設定コマンドを送りません。
    ///
    /// 責務: 最初のコマンドだけが送られ、取り消しで終わり、利用権がすぐ空くことを確認します。
    func testCancelledInitializationDoesNotSendFurtherCommands() async {
        makeStream()
        link.cancellingCommand = "ATZ"
        let initializer = AdapterLinkELMInitializer(stream: stream)

        let outcome = await AdapterLinkBoundedAwait.run("取り消された初期化") { try await initializer.initializeAdapter() }

        assertCancelled(outcome)
        XCTAssertEqual(link.writtenCommands, ["ATZ"])
        await assertLeaseIsAvailable()
    }

    /// 初期化の途中(識別問い合わせの書き込み中)で取り消されても、それ以降のコマンドを送りません。
    ///
    /// 責務: 取り消したコマンドが最後の送信で、受信監視などの後続コマンドが送られないことを確認します。
    func testCancellationMidInitializationStopsAtCancelledCommand() async {
        makeStream()
        link.cancellingCommand = "STI"
        let initializer = AdapterLinkELMInitializer(stream: stream)

        let outcome = await AdapterLinkBoundedAwait.run("途中で取り消された初期化") { try await initializer.initializeAdapter() }

        assertCancelled(outcome)
        XCTAssertEqual(link.writtenCommands.last, "STI")
        XCTAssertFalse(link.writtenCommands.contains("ATI"))
        await assertLeaseIsAvailable()
    }

    /// 応答待ち(最大30秒)の車両確認を取り消すと、待ち切らずに取り消しで終わり、利用権をすぐ手放します。
    ///
    /// 責務: 実時間のタイムアウトより十分前に終わり、続けて別の車両確認が成功することを確認します。
    func testCancellingPendingConfirmationReleasesLeaseImmediately() async throws {
        makeStream(timeScale: 1)
        link.replies["0100"] = nil
        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: stream)
        let task = Task { @MainActor in try await confirmer.confirmVehicleResponse(timeout: .adapterMaximum) }
        try await BLEBoundedWaiter.waitUntil("0100 の送信") { link.writtenCommands.contains("0100") }

        task.cancel()
        let outcome = await AdapterLinkBoundedAwait.outcome(of: task, "取り消した応答待ち")

        assertCancelled(outcome)
        link.replies["0100"] = AdapterLinkELMReplyFixtures.supportedPIDsPositive
        let next = await AdapterLinkBoundedAwait.run("次の車両確認") { try await confirmer.confirmVehicleResponse(timeout: .standard) }
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(next), .responding)
    }

    /// 取り消さなければ、同じ台本で車両確認は最後まで進みます(台本が取り消し以外で止まらないことの確認)。
    ///
    /// 責務: 取り消し指定なしで `0100` まで送られ「応答あり」になることを確認します。
    func testUncancelledConfirmationSendsRequest() async {
        makeStream()
        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: stream)

        let outcome = await AdapterLinkBoundedAwait.run("車両確認") { try await confirmer.confirmVehicleResponse(timeout: .adapterMaximum) }

        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), .responding)
        XCTAssertEqual(link.writtenCommands, ["ATSTFF", "0100"])
    }
}
