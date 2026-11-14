import XCTest
@testable import ProjectZD8

/// `BLEUARTDiscoveryAggregator` の探索結果の集約と送受信路の解決を検証します。
final class BLEUARTDiscoveryAggregatorTests: XCTestCase {
    private typealias Fixtures = BLEUARTCapabilityFixtures

    /// 生成直後は未完了で、解決できません。
    ///
    /// 責務: 初期状態の `hasServiceList` / `pendingServiceUUIDs` / `isComplete` / `resolveChannel()` を確認します。
    func testInitialStateIsIncomplete() {
        let aggregator = BLEUARTDiscoveryAggregator()
        XCTAssertFalse(aggregator.hasServiceList)
        XCTAssertTrue(aggregator.pendingServiceUUIDs.isEmpty)
        XCTAssertFalse(aggregator.isComplete)
        XCTAssertNil(aggregator.resolveChannel())
    }

    /// Service一覧は大文字化・重複除去・発見順の維持をして待機集合になります。
    ///
    /// 責務: `beginServices` の戻り値と待機集合を確認します。
    func testBeginServicesNormalizesDeduplicatesAndKeepsOrder() {
        var aggregator = BLEUARTDiscoveryAggregator()
        let pending = aggregator.beginServices(["fff0", "FFE0", "FFF0", "ffe0"])
        XCTAssertEqual(pending, ["FFF0", "FFE0"])
        XCTAssertEqual(aggregator.pendingServiceUUIDs, ["FFF0", "FFE0"])
        XCTAssertTrue(aggregator.hasServiceList)
        XCTAssertFalse(aggregator.isComplete)
    }

    /// 空のService一覧は直ちに完了扱いですが、解決はできません。
    ///
    /// 責務: Serviceなしの境界で `isComplete` が真、`resolveChannel()` が `nil` であることを確認します。
    func testEmptyServiceListIsCompleteButUnresolvable() {
        var aggregator = BLEUARTDiscoveryAggregator()
        XCTAssertEqual(aggregator.beginServices([]), [])
        XCTAssertTrue(aggregator.isComplete)
        XCTAssertNil(aggregator.resolveChannel())
    }

    /// 待機中のServiceだけを受け付け、重複・未要求・一覧前の記録は拒否します。
    ///
    /// 責務: `recordCharacteristics` の各分岐の戻り値を確認します。
    func testRecordCharacteristicsAcceptsOnlyPendingServicesOnce() {
        var aggregator = BLEUARTDiscoveryAggregator()
        XCTAssertFalse(aggregator.recordCharacteristics(serviceUUID: "FFF0", capabilities: []), "一覧前")
        _ = aggregator.beginServices(["FFF0", "FFE0"])

        XCTAssertTrue(aggregator.recordCharacteristics(serviceUUID: "fff0", capabilities: []), "小文字でも待機中なら受け付けます")
        XCTAssertFalse(aggregator.recordCharacteristics(serviceUUID: "FFF0", capabilities: []), "重複")
        XCTAssertFalse(aggregator.recordCharacteristics(serviceUUID: "180A", capabilities: []), "未要求")
        XCTAssertFalse(aggregator.isComplete)
        XCTAssertEqual(aggregator.pendingServiceUUIDs, ["FFE0"])

        XCTAssertTrue(aggregator.recordCharacteristics(serviceUUID: "FFE0", capabilities: []))
        XCTAssertTrue(aggregator.isComplete)
    }

    /// FFF0構成の能力がそろえば、write FFF2 / notify FFF1 の送受信路に解決します。
    ///
    /// 責務: 応答なし・応答あり・両方のそれぞれで書き込み種別を含めて解決結果を確認します。
    func testResolveChannelForFFF0SelectsWriteKind() {
        let cases: [(AppleBluetoothCharacteristicCapability, BLEWriteKind)] = [
            (Fixtures.writeWithoutResponseFFF2, .withoutResponse),
            (Fixtures.writeWithResponseFFF2, .withResponse),
            (Fixtures.writeBothFFF2, .withoutResponse)
        ]
        for (write, kind) in cases {
            let aggregator = completed(["FFF0": [Fixtures.notifyFFF1, write]])
            XCTAssertEqual(aggregator.resolveChannel(), BLEResolvedUARTChannel(
                serviceUUID: "FFF0",
                notifyCharacteristicUUID: "FFF1",
                writeCharacteristicUUID: "FFF2",
                writeKind: kind
            ), "\(write)")
        }
    }

    /// Notify能力またはWrite能力が欠けると解決できません。
    ///
    /// 責務: 必要な能力の欠落・Characteristicの欠落でそれぞれ `nil` になることを確認します。
    func testResolveChannelFailsWithoutRequiredCapabilities() {
        XCTAssertNil(completed(["FFF0": [Fixtures.nonNotifyFFF1, Fixtures.writeWithoutResponseFFF2]]).resolveChannel())
        XCTAssertNil(completed(["FFF0": [Fixtures.notifyFFF1, Fixtures.nonWritableFFF2]]).resolveChannel())
        XCTAssertNil(completed(["FFF0": [Fixtures.notifyFFF1]]).resolveChannel())
        XCTAssertNil(completed(["FFF0": [Fixtures.writeWithoutResponseFFF2]]).resolveChannel())
        XCTAssertNil(completed(["180A": [Fixtures.notifyFFF1, Fixtures.writeWithoutResponseFFF2]]).resolveChannel())
    }

    /// 全Service分そろうまでは、解決可能な能力があっても `nil` です。
    ///
    /// 責務: 未完了時に解決しないことを確認します。
    func testResolveChannelReturnsNilUntilComplete() {
        var aggregator = BLEUARTDiscoveryAggregator()
        _ = aggregator.beginServices(["FFF0", "180A"])
        _ = aggregator.recordCharacteristics(serviceUUID: "FFF0", capabilities: [Fixtures.notifyFFF1, Fixtures.writeWithoutResponseFFF2])
        XCTAssertNil(aggregator.resolveChannel())
    }

    /// 単一Characteristic構成(FFE0: FFE1がNotifyと書き込みを兼ねる)も解決します。
    ///
    /// 責務: notifyとwriteが同じCharacteristicの構成を確認します。
    func testResolveChannelForSingleCharacteristicFFE0() {
        let ffe1 = Fixtures.capability("FFE1", notify: true, withResponse: true)
        XCTAssertEqual(completed(["FFE0": [ffe1]]).resolveChannel(), BLEResolvedUARTChannel(
            serviceUUID: "FFE0",
            notifyCharacteristicUUID: "FFE1",
            writeCharacteristicUUID: "FFE1",
            writeKind: .withResponse
        ))
    }

    /// 複数の既知構成がそろう時は既知構成の優先順で選びます。
    ///
    /// 責務: FFE0とFFF0が両方解決できる時に `supported` で先のFFF0を選ぶことを確認します。
    func testResolveChannelPrefersEarlierSupportedProfile() {
        let ffe1 = Fixtures.capability("FFE1", notify: true, withResponse: true)
        let aggregator = completed([
            "FFE0": [ffe1],
            "FFF0": [Fixtures.notifyFFF1, Fixtures.writeWithoutResponseFFF2]
        ])
        XCTAssertEqual(aggregator.resolveChannel()?.serviceUUID, "FFF0")
    }

    /// 注入した構成だけで照合します。
    ///
    /// 責務: FFE0だけを指定した集約ではFFF0の能力を解決しないことを確認します。
    func testInjectedProfilesLimitResolution() {
        let ffe0Only = AppleBluetoothUARTProfile.supported.filter { $0.kind == .ffe0 }
        var aggregator = BLEUARTDiscoveryAggregator(profiles: ffe0Only)
        _ = aggregator.beginServices(["FFF0"])
        _ = aggregator.recordCharacteristics(serviceUUID: "FFF0", capabilities: [Fixtures.notifyFFF1, Fixtures.writeWithoutResponseFFF2])
        XCTAssertTrue(aggregator.isComplete)
        XCTAssertNil(aggregator.resolveChannel())
    }

    /// Service探索をやり直すと以前の集計を捨てます。
    ///
    /// 責務: 2回目の `beginServices` 後は未完了に戻り、以前の能力で解決しないことを確認します。
    func testBeginServicesAgainDiscardsPreviousCapabilities() {
        var aggregator = completed(["FFF0": [Fixtures.notifyFFF1, Fixtures.writeWithoutResponseFFF2]])
        XCTAssertNotNil(aggregator.resolveChannel())

        XCTAssertEqual(aggregator.beginServices(["FFF0"]), ["FFF0"])

        XCTAssertFalse(aggregator.isComplete)
        XCTAssertNil(aggregator.resolveChannel())
        _ = aggregator.recordCharacteristics(serviceUUID: "FFF0", capabilities: [Fixtures.notifyFFF1])
        XCTAssertNil(aggregator.resolveChannel())
    }

    /// 指定のService別能力を全て記録した集約を返します。
    ///
    /// 責務: Service一覧の記録と各Serviceの能力記録をまとめて行います。
    /// - Parameter services: Service UUIDごとの能力。
    /// - Returns: 全Service分を記録した集約。
    private func completed(_ services: [String: [AppleBluetoothCharacteristicCapability]]) -> BLEUARTDiscoveryAggregator {
        var aggregator = BLEUARTDiscoveryAggregator()
        let ordered = services.keys.sorted()
        _ = aggregator.beginServices(ordered)
        for service in ordered {
            _ = aggregator.recordCharacteristics(serviceUUID: service, capabilities: services[service] ?? [])
        }
        return aggregator
    }
}
