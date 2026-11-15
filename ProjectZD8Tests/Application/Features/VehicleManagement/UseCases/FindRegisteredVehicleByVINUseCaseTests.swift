import Foundation
import XCTest
@testable import ProjectZD8

/// `FindRegisteredVehicleByVINUseCase` が VIN でサインイン中アカウントの登録済み車両を照合することを検証します。
@MainActor
final class FindRegisteredVehicleByVINUseCaseTests: XCTestCase {
    /// サインイン中のアカウントです。
    private static let account = "account-a"

    /// 別のアカウントです。
    private static let otherAccount = "account-b"

    /// 代表VINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 車両の保存先 fake です。
    private let repository = AccountScopedVehicleRepositoryFake()

    /// 検証対象を作ります。
    ///
    /// 責務: fake を注入した照合ユースケースを返します。
    /// - Returns: 照合ユースケース。
    private func makeUseCase() -> FindRegisteredVehicleByVINUseCase {
        FindRegisteredVehicleByVINUseCase(repository: repository)
    }

    /// VIN が一致する車両を返します(大文字小文字と前後の空白を区別しません)。
    ///
    /// 責務: 小文字・空白付きのVINで登録済み車両が返ることを確認します。
    func testMatchingVINReturnsVehicleIgnoringCaseAndWhitespace() async throws {
        let target = VehicleProfile(vin: Self.vin, name: "BRZ")
        repository.vehiclesByAccount[Self.account] = [VehicleProfile(vin: "WVWZZZ1KZ6W000002", name: "Golf"), target]

        let found = try await makeUseCase().execute(vin: "  \(Self.vin.lowercased())\n", accountIdentifier: Self.account)

        XCTAssertEqual(found?.id, target.id)
        XCTAssertEqual(repository.loadedAccounts, [Self.account])
    }

    /// 登録済み車両側の VIN が小文字でも一致します。
    ///
    /// 責務: 比較が両側で大文字小文字を無視することを確認します。
    func testRegisteredLowercaseVINMatches() async throws {
        let target = VehicleProfile(vin: Self.vin.lowercased(), name: "BRZ")
        repository.vehiclesByAccount[Self.account] = [target]

        let found = try await makeUseCase().execute(vin: Self.vin, accountIdentifier: Self.account)

        XCTAssertEqual(found?.id, target.id)
    }

    /// 一致する車両が無ければ nil を返します。
    ///
    /// 責務: 不一致と、VIN が空の登録車両(OBD識別子のみの車両)が一致しないことを確認します。
    func testUnmatchedVINReturnsNil() async throws {
        repository.vehiclesByAccount[Self.account] = [
            VehicleProfile(vin: "WVWZZZ1KZ6W000002", name: "Golf"),
            VehicleProfile(vin: "", obdIdentifier: Self.vin, name: "ECU only"),
        ]

        let found = try await makeUseCase().execute(vin: Self.vin, accountIdentifier: Self.account)

        XCTAssertNil(found)
    }

    /// VIN が nil・空・空白だけなら nil を返します。
    ///
    /// 責務: VIN の無い要求で、VIN が空の登録車両に一致しないことを確認します。
    func testMissingVINReturnsNil() async throws {
        repository.vehiclesByAccount[Self.account] = [VehicleProfile(vin: "", obdIdentifier: "X", name: "ECU only")]

        for vin in [nil, "", "  \t\n"] as [String?] {
            let found = try await makeUseCase().execute(vin: vin, accountIdentifier: Self.account)
            XCTAssertNil(found, "\(String(describing: vin))")
        }
    }

    /// 別アカウントの車両とは一致しません。
    ///
    /// 責務: 同じVINの車両が別アカウントにだけある時に nil となり、別アカウントを読まないことを確認します。
    func testVehicleOfOtherAccountDoesNotMatch() async throws {
        repository.vehiclesByAccount[Self.otherAccount] = [VehicleProfile(vin: Self.vin, name: "Other's")]

        let found = try await makeUseCase().execute(vin: Self.vin, accountIdentifier: Self.account)

        XCTAssertNil(found)
        XCTAssertFalse(repository.loadedAccounts.contains(Self.otherAccount))
    }

    /// アカウントが無い(nil・空)なら nil を返します。
    ///
    /// 責務: 未サインインで照合結果が出ないことを確認します。
    func testMissingAccountReturnsNil() async throws {
        repository.vehiclesByAccount[""] = [VehicleProfile(vin: Self.vin, name: "BRZ")]

        for account in [nil, ""] as [String?] {
            let found = try await makeUseCase().execute(vin: Self.vin, accountIdentifier: account)
            XCTAssertNil(found, "\(String(describing: account))")
        }
    }

    /// 同じ VIN の車両が複数あっても、そのアカウントの該当車両のどれかが返ります。
    ///
    /// 責務: 選び方は固定せず、返る車両がそのアカウントの同じVINの車両であることを確認します。
    func testDuplicateVINReturnsOneOfAccountVehicles() async throws {
        let first = VehicleProfile(vin: Self.vin, name: "First")
        let second = VehicleProfile(vin: Self.vin.lowercased(), name: "Second")
        repository.vehiclesByAccount[Self.account] = [first, second]
        repository.vehiclesByAccount[Self.otherAccount] = [VehicleProfile(vin: Self.vin, name: "Other's")]

        let found = try await makeUseCase().execute(vin: Self.vin, accountIdentifier: Self.account)

        let id = try XCTUnwrap(found?.id)
        XCTAssertTrue([first.id, second.id].contains(id))
    }

    /// Repository の読込失敗は throw します。
    ///
    /// 責務: 失敗を nil(不一致)に潰さず、同じエラーで伝えることを確認します。
    func testRepositoryFailureThrows() async {
        repository.vehiclesByAccount[Self.account] = [VehicleProfile(vin: Self.vin, name: "BRZ")]
        repository.loadFailure = VehicleRecordingTestError.vehicleLoadFailed

        do {
            let found = try await makeUseCase().execute(vin: Self.vin, accountIdentifier: Self.account)
            XCTFail("throw するはずが値を返しました: \(String(describing: found))")
        } catch {
            XCTAssertEqual(error as? VehicleRecordingTestError, .vehicleLoadFailed)
        }
    }
}
