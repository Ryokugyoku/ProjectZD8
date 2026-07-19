import XCTest
@testable import ProjectZD8

/// デフォルトアダプターの共通接続可否判定を検証します。
final class DefaultAdapterAvailabilityTests: XCTestCase {
    /// 保存設定がない場合は未設定状態になることを検証します。
    ///
    /// 責務: デフォルト設定がない入力を接続不能な未設定状態へ変換することを確認します。
    func testMissingPreferenceIsNotConfigured() {
        let availability = DefaultAdapterAvailability(
            preference: nil,
            detectedAdapter: makeAdapter(id: "detected")
        )

        XCTAssertEqual(availability, .notConfigured)
        XCTAssertFalse(availability.hasDefaultAdapter)
        XCTAssertNil(availability.connectionEndpoint)
    }

    /// 保存済み候補が最新探索に存在しない場合は未検出状態になることを検証します。
    ///
    /// 責務: 保存設定だけが残る入力から接続終端を公開しないことを確認します。
    func testSavedButMissingAdapterIsNotDetected() {
        let savedAdapter = makeAdapter(id: "saved", name: "Saved Adapter")

        let availability = DefaultAdapterAvailability(
            preference: DefaultAdapterPreference(adapter: savedAdapter),
            detectedAdapter: nil
        )

        XCTAssertEqual(availability, .notDetected(displayName: "Saved Adapter"))
        XCTAssertTrue(availability.hasDefaultAdapter)
        XCTAssertFalse(availability.isDetected)
        XCTAssertNil(availability.connectionEndpoint)
    }

    /// 保存設定と一致する最新候補だけが接続終端を公開することを検証します。
    ///
    /// 責務: 一致する検出候補を接続可能状態と現在の物理終端へ変換することを確認します。
    func testMatchingDetectedAdapterExposesConnectionEndpoint() {
        let adapter = makeAdapter(id: "saved", name: "Saved Adapter")

        let availability = DefaultAdapterAvailability(
            preference: DefaultAdapterPreference(adapter: adapter),
            detectedAdapter: adapter
        )

        XCTAssertTrue(availability.isDetected)
        XCTAssertEqual(availability.connectionEndpoint, OBDConnectionEndpoint(adapter: adapter))
    }

    /// テスト用Bluetoothアダプター候補を生成します。
    ///
    /// 責務: 指定した識別子と名称を持つ未接続候補を1件構築します。
    /// - Parameters:
    ///   - id: 候補を識別する安定識別子。
    ///   - name: 候補の表示名称。
    /// - Returns: 共通接続可否テストで使用するBluetooth候補。
    private func makeAdapter(id: String, name: String = "Adapter") -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .bluetooth,
            displayName: name,
            systemIdentifier: id,
            isConnected: false
        )
    }
}
