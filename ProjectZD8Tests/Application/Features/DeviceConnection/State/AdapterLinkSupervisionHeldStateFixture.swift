import XCTest
@testable import ProjectZD8

/// ユーザー切断後の抑止状態を、仕様の入口(記録中に `.userDisconnected` で終了)から作るテスト用の組み立てです。
///
/// 抑止状態の値そのものは直接書かず、仕様どおりの入力から得た状態を使います。
@MainActor
enum AdapterLinkSupervisionHeldStateFixture {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 検証対象の遷移です。
    static let transition = AdapterLinkSupervisionTransition()

    /// 記録中にユーザー切断で終了した直後の状態を返します。
    ///
    /// 責務: 仕様の入口を実行し、待機でも終了中でもない抑止状態になることを確認したうえで、その状態を返します。
    /// - Returns: 抑止状態。
    static func heldAfterUserStop(file: StaticString = #filePath, line: UInt = #line) -> AdapterLinkSupervisionState {
        let result = transition.result(
            from: .recording(F.detectedVehicle),
            on: .recordingDidFinish(endReason: .userDisconnected),
            conditions: F.conditions()
        )
        XCTAssertNotEqual(result.state, .standby, "抑止状態は待機とは別", file: file, line: line)
        XCTAssertNotEqual(result.state, .finishing, "抑止状態は終了中を経由しない", file: file, line: line)
        XCTAssertEqual(result.effects, [.dismissNotification], "作用は通知の取り下げだけ", file: file, line: line)
        return result.state
    }
}
