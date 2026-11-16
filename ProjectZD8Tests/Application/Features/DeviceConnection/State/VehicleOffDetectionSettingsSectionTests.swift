import XCTest
@testable import ProjectZD8

/// `VehicleOffDetectionSettingsSection` の選択肢・選択状態・文言キーを検証します。
final class VehicleOffDetectionSettingsSectionTests: XCTestCase {
    /// 選択肢は10・30・60・180秒の順で、選択中の値によらず同じです。
    ///
    /// 責務: `choices` の内容と順序を確認します。
    func testChoicesAreAllDelaysInOrder() {
        for selected in VehicleOffDetectionDelay.allCases {
            let section = VehicleOffDetectionSettingsSection(selectedDelay: selected)

            XCTAssertEqual(section.choices.map(\.rawValue), [10, 30, 60, 180])
        }
    }

    /// 選択中の値だけが選択状態です。
    ///
    /// 責務: 4つの選択中の値それぞれで、`isSelected` が1つだけ真になることを確認します。
    func testOnlySelectedDelayIsSelected() {
        for selected in VehicleOffDetectionDelay.allCases {
            let section = VehicleOffDetectionSettingsSection(selectedDelay: selected)

            for candidate in VehicleOffDetectionDelay.allCases {
                XCTAssertEqual(section.isSelected(candidate), candidate == selected, "selected=\(selected) candidate=\(candidate)")
            }
        }
    }

    /// 選択肢ごとの文言キーは秒数を含む固定のキーです。
    ///
    /// 責務: `titleKey(for:)` の4つのキーをリテラルで確認します。
    func testTitleKeyPerDelay() {
        XCTAssertEqual(VehicleOffDetectionSettingsSection.titleKey(for: .seconds10), "settings.vehicle_off.delay.10")
        XCTAssertEqual(VehicleOffDetectionSettingsSection.titleKey(for: .seconds30), "settings.vehicle_off.delay.30")
        XCTAssertEqual(VehicleOffDetectionSettingsSection.titleKey(for: .seconds60), "settings.vehicle_off.delay.60")
        XCTAssertEqual(VehicleOffDetectionSettingsSection.titleKey(for: .seconds180), "settings.vehicle_off.delay.180")
    }

    /// 見出し・説明の文言キーは固定です。
    ///
    /// 責務: 静的な3つの文言キーを確認します。
    func testStaticKeys() {
        XCTAssertEqual(VehicleOffDetectionSettingsSection.eyebrowKey, "settings.vehicle_off.eyebrow")
        XCTAssertEqual(VehicleOffDetectionSettingsSection.titleKey, "settings.vehicle_off.title")
        XCTAssertEqual(VehicleOffDetectionSettingsSection.descriptionKey, "settings.vehicle_off.description")
    }

    /// 同じ選択なら等価で、違えば等価でありません。
    ///
    /// 責務: `Equatable` が選択中の値を区別することを確認します。
    func testEqualityFollowsSelection() {
        XCTAssertEqual(
            VehicleOffDetectionSettingsSection(selectedDelay: .seconds60),
            VehicleOffDetectionSettingsSection(selectedDelay: .seconds60)
        )
        XCTAssertNotEqual(
            VehicleOffDetectionSettingsSection(selectedDelay: .seconds60),
            VehicleOffDetectionSettingsSection(selectedDelay: .seconds10)
        )
    }
}
