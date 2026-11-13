import XCTest
@testable import ProjectZD8

/// PID定義取得と数値変換のApplication境界を検証します。
final class DecodeOBDPIDValueUseCaseTests: XCTestCase {
    /// 登録済み式と単位を変換結果へ反映します。
    ///
    /// 責務: Service/PIDに対応する式が応答バイトへ一度だけ適用されることを確認します。
    func testExecuteDecodesRegisteredDefinition() throws {
        let repository = OBDPIDDefinitionRepositoryFake(
            storedDefinition: OBDPIDDefinition(
                service: 0x01,
                pid: 0x0C,
                nameKey: "obd.pid.01.0C.name",
                requiredByteCount: 2,
                formula: "(A * 256 + B) / 4",
                unit: "rpm",
                minimumValue: 0,
                maximumValue: 16_383.75,
                sourceURI: "https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327DSH.pdf",
                revision: 1
            )
        )
        let useCase = DecodeOBDPIDValueUseCase(repository: repository)

        let result = try useCase.execute(service: 0x01, pid: 0x0C, bytes: [0x1A, 0xF8])

        XCTAssertEqual(result?.value, 1_726)
        XCTAssertEqual(result?.unit, "rpm")
        XCTAssertEqual(repository.lastLookup, .init(service: 0x01, pid: 0x0C))
    }

    /// 未登録PIDを推測式で変換しません。
    ///
    /// 責務: 定義が存在しないService/PIDを未対応として返すことを確認します。
    func testExecuteReturnsNilForUnknownPID() throws {
        let repository = OBDPIDDefinitionRepositoryFake(storedDefinition: nil)
        let useCase = DecodeOBDPIDValueUseCase(repository: repository)

        let result = try useCase.execute(service: 0x01, pid: 0xFF, bytes: [0x00])

        XCTAssertNil(result)
    }
}

/// PID変換UseCaseへ決定的な定義を返すテスト用リポジトリです。
private final class OBDPIDDefinitionRepositoryFake: OBDPIDDefinitionRepository {
    /// 最後に検索された複合識別子です。
    private(set) var lastLookup: Lookup?
    /// 取得時に返す定義です。
    private let storedDefinition: OBDPIDDefinition?

    /// テストで返す定義を固定して生成します。
    ///
    /// 責務: 1件の取得シナリオへ返却定義を固定します。
    /// - Parameter storedDefinition: 取得時に返す定義。未登録シナリオでは `nil`。
    init(storedDefinition: OBDPIDDefinition?) {
        self.storedDefinition = storedDefinition
    }

    /// このテストでは使用しないPID定義一覧を返します。
    ///
    /// 責務: 単一定義読取テストで一覧要求へ空配列を返します。
    /// - Returns: 常に空のPID定義一覧。
    func definitions() throws -> [OBDPIDDefinition] { [] }

    /// 保存処理をテスト対象外として受け入れます。
    ///
    /// 責務: 読取専用UseCaseテストで不要な保存呼出しを明示的に無視します。
    /// - Parameter definition: 使用しないPID定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// 固定定義を返して検索キーを記録します。
    ///
    /// 責務: 1件のService/PID検索を観測して固定結果を返します。
    /// - Parameters:
    ///   - service: 検索されたService番号。
    ///   - pid: 検索されたPID番号。
    /// - Returns: 初期化時に指定された定義。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? {
        lastLookup = Lookup(service: service, pid: pid)
        return storedDefinition
    }

    /// テストで観測するService/PID複合キーです。
    struct Lookup: Equatable {
        /// OBD Service番号です。
        let service: UInt8
        /// Service内PID番号です。
        let pid: UInt8

        /// Service/PID複合キーを生成します。
        ///
        /// 責務: 1件の検索Service番号とPID番号を比較可能な値へ固定します。
        /// - Parameters:
        ///   - service: OBD Service番号。
        ///   - pid: Service内PID番号。
        init(service: UInt8, pid: UInt8) {
            self.service = service
            self.pid = pid
        }
    }
}
