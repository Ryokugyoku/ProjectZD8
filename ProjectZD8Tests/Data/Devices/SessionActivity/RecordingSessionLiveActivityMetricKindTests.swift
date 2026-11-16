import Foundation
import XCTest
@testable import ProjectZD8

/// `RecordingSessionLiveActivityMetricKind` の並び・見出しと単位のキー・表示内容からの計測値の取り出しを検証します。
///
/// 仕様: U5 受け入れ条件 10・13(B14)。
final class RecordingSessionLiveActivityMetricKindTests: XCTestCase {
    /// 項目は車速・エンジン回転数・スロットル開度の順の3つです。
    ///
    /// 責務: `allCases` の並びを確認します。
    func testAllCasesOrder() {
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.allCases, [.vehicleSpeed, .engineSpeed, .throttlePosition])
    }

    /// 見出しと単位のキーは項目ごとに決まっています。
    ///
    /// 責務: 3項目の `labelKey`・`unitKey` を確認します。
    func testLabelAndUnitKeys() {
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.vehicleSpeed.labelKey, "live_activity.label.vehicle_speed")
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.engineSpeed.labelKey, "live_activity.label.engine_speed")
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.throttlePosition.labelKey, "live_activity.label.throttle_position")
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.vehicleSpeed.unitKey, "live_activity.unit.vehicle_speed")
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.engineSpeed.unitKey, "live_activity.unit.engine_speed")
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.throttlePosition.unitKey, "live_activity.unit.throttle_position")
    }

    /// 見出しと単位のキーは、文字列カタログに ja・en・es の値を持ちます。
    ///
    /// 責務: 6つのキーと3言語の組で値が空でないことを確認します。
    func testKeysExistInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("ProjectZD8/Resources/Localization/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any])
        let keys = RecordingSessionLiveActivityMetricKind.allCases.flatMap { [$0.labelKey, $0.unitKey] }
        for key in keys {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            for language in ["ja", "en", "es"] {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = try XCTUnwrap(unit?["value"] as? String, "\(key) / \(language)")
                XCTAssertFalse(value.isEmpty, "\(key) / \(language)")
            }
        }
    }

    /// 項目ごとに、表示内容の対応する計測値を取り出します。
    ///
    /// 責務: 3項目が別々の値を持つ表示内容から、それぞれの値を取り出すことを確認します。
    func testMetricInState() {
        let state = RecordingSessionActivityAttributes.ContentState(
            vehicle: .unregistered,
            statusKey: "live_activity.status.recording",
            statusTone: .normal,
            vehicleSpeed: .value(60),
            engineSpeed: .value(3_000),
            throttlePosition: .unavailable,
            receivedResponseCount: 0,
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            vehiclePhotoFileName: nil
        )
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.vehicleSpeed.metric(in: state), .value(60))
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.engineSpeed.metric(in: state), .value(3_000))
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.throttlePosition.metric(in: state), .unavailable)
    }
}
