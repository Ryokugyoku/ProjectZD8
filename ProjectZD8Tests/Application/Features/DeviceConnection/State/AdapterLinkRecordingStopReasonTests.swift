import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingStopReason` の、稼働条件の変化からの理由の決め方と、保存する終了理由への写し方を検証します。
///
/// 仕様(U2 受け入れ条件 9〜12 と管理チャットの決定):
/// - 判定順は 未サインイン → 監視停止 → 接続対象なし → 別のアダプター。
/// - 既定アダプターを別のアダプターへ変えた(別の BLE・Classic・シリアル)なら置き換え、既定アダプターの削除と監視の停止は接続断。
@MainActor
final class AdapterLinkRecordingStopReasonTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// サインアウトは、単独でも他の理由と同時でも `accountSignedOut` です。
    ///
    /// 責務: 未サインインが監視停止・接続対象なし・別のアダプターより優先されることを確認します(決定 ii)。
    func testSignedOutTakesPriorityOverEveryOtherReason() {
        let variants: [AdapterLinkSupervisionConditions] = [
            F.conditions(isSignedIn: false),
            F.conditions(isSupervisionStarted: false, isSignedIn: false),
            F.conditions(isSignedIn: false, defaultAdapterPreference: nil),
            F.conditions(isSignedIn: false, defaultAdapterPreference: F.otherBLEPreference),
            F.conditions(isSignedIn: false, defaultAdapterPreference: F.classicPreference),
        ]
        for conditions in variants {
            XCTAssertEqual(AdapterLinkRecordingStopReason.forOperatingConditionsChange(conditions), .accountSignedOut, "\(conditions)")
        }
    }

    /// サインイン中の監視停止は、接続対象の有無にかかわらず `supervisionStopped` です。
    ///
    /// 責務: 監視停止が接続対象なし・別のアダプターより優先されることを確認します(決定 ii)。
    func testSupervisionStoppedTakesPriorityOverTarget() {
        let variants: [AdapterLinkSupervisionConditions] = [
            F.conditions(isSupervisionStarted: false),
            F.conditions(isSupervisionStarted: false, defaultAdapterPreference: nil),
            F.conditions(isSupervisionStarted: false, defaultAdapterPreference: F.otherBLEPreference),
        ]
        for conditions in variants {
            XCTAssertEqual(AdapterLinkRecordingStopReason.forOperatingConditionsChange(conditions), .supervisionStopped, "\(conditions)")
        }
    }

    /// 既定アダプターが無くなったら `connectionTargetLost` です。
    ///
    /// 責務: サインイン中・監視中で既定アダプターが無い時の理由を確認します(仕様 11)。
    func testRemovedDefaultAdapterIsConnectionTargetLost() {
        let conditions = F.conditions(defaultAdapterPreference: nil)
        XCTAssertEqual(AdapterLinkRecordingStopReason.forOperatingConditionsChange(conditions), .connectionTargetLost)
    }

    /// 既定アダプターを別のアダプター(別の BLE・Classic・シリアル)へ変えたら `superseded` です。
    ///
    /// 責務: 接続対象が別のアダプターに置き換わる3通りの理由を確認します(仕様 10、決定 i)。
    func testChangedDefaultAdapterIsSuperseded() {
        for preference in [F.otherBLEPreference, F.classicPreference, F.serialPreference] {
            let conditions = F.conditions(defaultAdapterPreference: preference)
            XCTAssertEqual(AdapterLinkRecordingStopReason.forOperatingConditionsChange(conditions), .superseded, "\(preference)")
        }
    }

    /// 保存する終了理由は、サインアウト→`accountSignedOut`、置き換え→`superseded`、接続対象なし・監視停止→`connectionLost` です。
    ///
    /// 責務: 4つの理由すべての写し先と、どれも `userDisconnected` にならないことを確認します(仕様 9〜12)。
    func testSessionEndReasonForEveryStopReason() {
        let expected: [(AdapterLinkRecordingStopReason, ConnectionSessionEndReason)] = [
            (.accountSignedOut, .accountSignedOut),
            (.superseded, .superseded),
            (.connectionTargetLost, .connectionLost),
            (.supervisionStopped, .connectionLost),
        ]
        for (reason, endReason) in expected {
            XCTAssertEqual(reason.sessionEndReason, endReason, "\(reason)")
            XCTAssertNotEqual(reason.sessionEndReason, .userDisconnected, "\(reason)")
        }
    }
}
