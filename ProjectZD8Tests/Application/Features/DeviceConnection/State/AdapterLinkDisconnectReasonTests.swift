import XCTest
@testable import ProjectZD8

/// `AdapterLinkDisconnectReason.isTerminal` の分類を検証します。
final class AdapterLinkDisconnectReasonTests: XCTestCase {
    /// 未知プロファイル・再試行上限超過・不正な識別子は終端です。
    ///
    /// 責務: 自動でやり直さない理由が全て `true` になることを確認します。
    func testTerminalReasons() {
        let reasons: [AdapterLinkDisconnectReason] = [.unknownUARTProfile, .retryLimitExceeded, .invalidIdentifier]
        reasons.forEach { XCTAssertTrue($0.isTerminal, "\($0)") }
    }

    /// Bluetooth利用不可・切断・接続失敗・探索失敗・探索待機超過は終端ではありません。
    ///
    /// 責務: 自動でやり直す理由が説明の有無にかかわらず全て `false` になることを確認します。
    func testNonTerminalReasons() {
        let reasons: [AdapterLinkDisconnectReason] = [
            .bluetoothPoweredOff,
            .bluetoothUnauthorized,
            .bluetoothUnsupported,
            .peripheralDisconnected(errorDescription: nil),
            .peripheralDisconnected(errorDescription: "timeout"),
            .connectionFailed(errorDescription: nil),
            .connectionFailed(errorDescription: "failed"),
            .discoveryFailed(errorDescription: nil),
            .discoveryFailed(errorDescription: "failed"),
            .discoveryTimedOut
        ]
        reasons.forEach { XCTAssertFalse($0.isTerminal, "\($0)") }
    }
}
