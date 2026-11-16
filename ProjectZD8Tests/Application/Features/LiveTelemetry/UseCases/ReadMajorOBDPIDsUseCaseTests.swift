import Foundation
import XCTest
@testable import ProjectZD8

/// PID定義DBから読取対象の定義を選ぶ処理(全件・車両別)と、PID通信セッションの終了通知を検証します。
///
/// 未登録車両用の標準定義の選別は `ReadMajorOBDPIDsUseCaseStandardDefinitionsTests` が検証します。
@MainActor
final class ReadMajorOBDPIDsUseCaseTests: XCTestCase {
    // MARK: - loadDefinitions()

    /// DBの定義のうち数値化できるものだけを、DBの順で返します(車種専用の定義も含みます)。
    ///
    /// 責務: 数値化の可否だけで除外し、DBから読んだ定義を返すことを確認します。
    func testLoadDefinitionsReturnsDecodableDefinitionsFromRepository() throws {
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C])
            + [undecodable(pid: 0x0D, formula: nil), undecodable(pid: 0x0F, requiredByteCount: nil), undecodable(pid: 0x10, formula: "")]
            + [vehicleSpecific(pid: 0x20)]

        let definitions = try makeUseCase(catalog: catalog).loadDefinitions()

        XCTAssertEqual(definitions, LiveTelemetryTestDefinitions.standard([0x05, 0x0C]) + [vehicleSpecific(pid: 0x20)])
    }

    /// DBが空、または数値化できる定義が1件も無ければ、カタログ利用不能として失敗します。
    ///
    /// 責務: 空の結果を成功にしないことを確認します。
    func testLoadDefinitionsThrowsWhenNoDecodableDefinitionExists() {
        let catalogs = [[], [undecodable(pid: 0x0D, formula: nil)]]

        for catalog in catalogs {
            XCTAssertThrowsError(try makeUseCase(catalog: catalog).loadDefinitions(), "件数: \(catalog.count)") {
                XCTAssertEqual($0 as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
            }
        }
    }

    /// DBの読込に失敗したら、カタログ利用不能として失敗します。
    ///
    /// 責務: 読込失敗を成功や空データにせず、取得境界のエラーへ変換することを確認します。
    func testLoadDefinitionsMapsRepositoryFailureToCatalogUnavailable() {
        let useCase = makeUseCase(catalog: LiveTelemetryTestDefinitions.standard([0x05]), failsRead: true)

        XCTAssertThrowsError(try useCase.loadDefinitions()) {
            XCTAssertEqual($0 as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
        }
    }

    // MARK: - loadDefinitions(for:)

    /// 車両の対応PIDのうち収集有効なものに一致する、数値化できる定義だけを返します。
    ///
    /// 責務: 収集無効・定義の無い対応PID・数値化できない定義を除くことを確認します。
    func testLoadDefinitionsForCapabilitiesSelectsEnabledDecodableDefinitions() throws {
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C, 0x11]) + [undecodable(pid: 0x0D, formula: nil)]
        let capabilities = [
            capability(0x05, enabled: true),
            capability(0x0C, enabled: false),
            capability(0x0D, enabled: true),
            capability(0x2F, enabled: true),
            capability(0x11, enabled: true)
        ]

        let definitions = try makeUseCase(catalog: catalog).loadDefinitions(for: capabilities)

        XCTAssertEqual(definitions.map(LiveTelemetryTestDefinitions.request), [0x05, 0x11].map(LiveTelemetryTestDefinitions.request))
    }

    /// 対応PIDが無い・すべて収集無効・一致する定義が無い場合は、カタログ利用不能として失敗します。
    ///
    /// 責務: 選べる定義が空の時に成功しないことを確認します。
    func testLoadDefinitionsForCapabilitiesThrowsWhenNothingSelectable() {
        let useCase = makeUseCase(catalog: LiveTelemetryTestDefinitions.standard([0x05, 0x0C]))
        let cases: [[VehiclePIDCapability]] = [
            [],
            [capability(0x05, enabled: false), capability(0x0C, enabled: false)],
            [capability(0x2F, enabled: true)]
        ]

        for capabilities in cases {
            XCTAssertThrowsError(try useCase.loadDefinitions(for: capabilities), "対応PID: \(capabilities.count)件") {
                XCTAssertEqual($0 as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
            }
        }
    }

    /// DBの読込に失敗したら、収集有効な対応PIDがあってもカタログ利用不能として失敗します。
    ///
    /// 責務: 車両別の選択でも読込失敗を成功にしないことを確認します。
    func testLoadDefinitionsForCapabilitiesThrowsWhenRepositoryFails() {
        let useCase = makeUseCase(catalog: LiveTelemetryTestDefinitions.standard([0x05]), failsRead: true)

        XCTAssertThrowsError(try useCase.loadDefinitions(for: [capability(0x05, enabled: true)])) {
            XCTAssertEqual($0 as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
        }
    }

    // MARK: - loadStandardDefinitions(supported:)

    /// ECUが対応を1件も返さなければ、カタログ利用不能として失敗します。
    ///
    /// 責務: 対応一覧が空の境界で成功しないことを確認します。
    func testLoadStandardDefinitionsThrowsWhenSupportedIsEmpty() {
        let useCase = makeUseCase(catalog: LiveTelemetryTestDefinitions.standard([0x05, 0x0C]))

        XCTAssertThrowsError(try useCase.loadStandardDefinitions(supported: [])) {
            XCTAssertEqual($0 as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
        }
    }

    // MARK: - endSession()

    /// 終了を1回呼ぶと、取得境界へ終了が1回だけ伝わり、読取は行いません。
    ///
    /// 責務: 終了通知を取得境界へそのまま委ねることを確認します。
    func testEndSessionNotifiesTelemetryOnce() async {
        let telemetry = ScriptedOBDPIDTelemetryFake()
        let useCase = ReadMajorOBDPIDsUseCase(
            definitionRepository: StubOBDPIDDefinitionRepository(definitions: LiveTelemetryTestDefinitions.standard([0x05])),
            telemetry: telemetry
        )

        await useCase.endSession()

        XCTAssertEqual(telemetry.endSessionCount, 1)
        XCTAssertTrue(telemetry.observationRequests.isEmpty)
        XCTAssertTrue(telemetry.vehicleSpecificDefinitions.isEmpty)
    }

    // MARK: - Helpers

    /// カタログを指定して定義読込のユースケースを作ります。
    ///
    /// 責務: 通信しない取得境界で定義読込のユースケースを返します。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。
    ///   - failsRead: カタログ読込を失敗させる場合は `true`。
    /// - Returns: 定義読込のユースケース。
    private func makeUseCase(catalog: [OBDPIDDefinition], failsRead: Bool = false) -> ReadMajorOBDPIDsUseCase {
        ReadMajorOBDPIDsUseCase(
            definitionRepository: StubOBDPIDDefinitionRepository(definitions: catalog, failsRead: failsRead),
            telemetry: ScriptedOBDPIDTelemetryFake()
        )
    }

    /// 数値化できない Service 01 の定義を作ります。
    ///
    /// 責務: 必要バイト数または式を欠いた定義を返します。
    /// - Parameters:
    ///   - pid: Service 01 内のPID番号。
    ///   - requiredByteCount: 必要バイト数。
    ///   - formula: 変換式。
    /// - Returns: 数値化できない定義。
    private func undecodable(pid: UInt8, requiredByteCount: Int? = 1, formula: String? = "A") -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x01, pid: pid, nameKey: "test.undecodable.\(pid)", requiredByteCount: requiredByteCount, formula: formula,
            unit: "unit", minimumValue: nil, maximumValue: nil, sourceURI: "test://pid", revision: 1
        )
    }

    /// 数値化できる車種専用の定義を作ります。
    ///
    /// 責務: ヘッダーと車種コードを持つ定義を返します。
    /// - Parameter pid: PID番号。
    /// - Returns: 車種専用の定義。
    private func vehicleSpecific(pid: UInt8) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x22, pid: pid, header: 0x7E0, vehicleModelCode: "ZD8", nameKey: "test.vehicle.\(pid)", requiredByteCount: 1,
            formula: "A", unit: "unit", minimumValue: 0, maximumValue: 255, sourceURI: "test://pid", revision: 1
        )
    }

    /// テスト用車両の Service 01 対応PIDを作ります。
    ///
    /// 責務: PID番号と収集の有効・無効だけを変えた対応PIDを返します。
    /// - Parameters:
    ///   - pid: Service 01 内のPID番号。
    ///   - enabled: 収集有効かどうか。
    /// - Returns: 車両別の対応PID。
    private func capability(_ pid: UInt8, enabled: Bool) -> VehiclePIDCapability {
        VehiclePIDCapability(
            vehicleID: LiveTelemetryTestDefinitions.vehicleID,
            request: LiveTelemetryTestDefinitions.request(pid),
            isCollectionEnabled: enabled,
            discoveredAt: Date(timeIntervalSince1970: 1)
        )
    }
}
