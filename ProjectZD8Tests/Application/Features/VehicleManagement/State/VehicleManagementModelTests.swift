import Foundation
import XCTest
@testable import ProjectZD8

/// 車両管理モデルが識別失敗を原因別の表示状態へ変換することを検証します。
@MainActor
final class VehicleManagementModelTests: XCTestCase {
    /// 識別境界の型付きエラーを診断可能な表示キーへ分離します。
    ///
    /// 責務: 実車識別の主要失敗段階が同じ汎用文言へ潰れないことを確認します。
    func testIdentificationErrorsUseStageSpecificFailureKeys() async throws {
        let expectations: [(VehicleIdentificationError, String)] = [
            (.pidCatalogUnavailable, "garage.error.pid_catalog"),
            (.connectionFailed, "garage.error.connection"),
            (.responseTimedOut, "garage.error.timeout"),
            (.commandRejected, "garage.error.command_rejected"),
            (.malformedResponse, "garage.error.malformed_response")
        ]

        for (error, expectedKey) in expectations {
            let model = makeModel(error: error)
            model.send(.accountIdentifierChanged("test-account"))
            try await waitUntil { model.state.hasLoadedVehicles }

            model.send(.identifyRequested(endpoint))
            try await waitUntil { model.state.phase == .failed }

            XCTAssertEqual(model.state.failureKey, expectedKey)
        }
    }

    /// 指定識別エラーを返す車両管理モデルを生成します。
    ///
    /// 責務: 1件の識別失敗を観測できるテスト用依存関係を組み立てます。
    /// - Parameter error: 識別境界から返す型付きエラー。
    /// - Returns: 空の車両一覧を読み込み済みにできる車両管理モデル。
    private func makeModel(error: VehicleIdentificationError) -> VehicleManagementModel {
        VehicleManagementModel(
            state: VehicleManagementState(),
            repository: VehicleRepositoryFake(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: FailingVehicleIdentificationPort(error: error)
            ),
            photoImporter: VehiclePhotoImportPortFake()
        )
    }

    /// テスト用のEXシリアル終端です。
    private var endpoint: OBDConnectionEndpoint {
        .init(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "OBDLink EX")
    }

    /// 指定条件が成立するまでMainActor上の非同期処理へ実行機会を渡します。
    ///
    /// 責務: 1件のモデル状態条件を上限回数内で待機します。
    /// - Parameter condition: 成立を待つ状態条件。
    /// - Throws: 上限回数までに条件が成立しない場合のテスト失敗。
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { await Task.yield() }
        guard condition() else { throw VehicleManagementModelTestError.conditionTimedOut }
    }
}

/// 車両管理モデルテストの待機失敗です。
private enum VehicleManagementModelTestError: Error {
    /// 期待状態が上限回数までに成立しませんでした。
    case conditionTimedOut
}

/// 車両管理テストへ空の保存状態を提供します。
@MainActor
private final class VehicleRepositoryFake: VehicleRepository {
    /// 空の登録車両一覧を返します。
    ///
    /// 責務: 指定アカウントのテスト用車両一覧を空として返します。
    /// - Parameter accountIdentifier: テスト用アカウント識別子。
    /// - Returns: 空の車両一覧。
    func loadVehicles(for accountIdentifier: String) async throws -> [VehicleProfile] { [] }

    /// テストでは車両を保存しません。
    ///
    /// 責務: 車両保存要求を副作用なしで受理します。
    /// - Parameters:
    ///   - vehicle: 保存対象として受け取る車両。
    ///   - accountIdentifier: テスト用アカウント識別子。
    func saveVehicle(_ vehicle: VehicleProfile, for accountIdentifier: String) async throws {}

    /// テストでは車両を削除しません。
    ///
    /// 責務: 車両削除要求を副作用なしで受理します。
    /// - Parameters:
    ///   - id: 削除対象として受け取る車両ID。
    ///   - accountIdentifier: テスト用アカウント識別子。
    func deleteVehicle(id: VehicleID, for accountIdentifier: String) async throws {}
}

/// 注入された識別エラーだけを返す境界です。
private struct FailingVehicleIdentificationPort: VehicleIdentificationPort {
    /// すべての識別要求で返すエラーです。
    let error: VehicleIdentificationError

    /// 指定された型付きエラーで識別を失敗させます。
    ///
    /// 責務: 1件の車両識別要求へ注入済みエラーを返します。
    /// - Parameter endpoint: テストでは参照しない接続終端。
    /// - Throws: 初期化時に注入された識別エラー。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        throw error
    }
}

/// 車両管理テストで画像取込を使用不能に保つ境界です。
private struct VehiclePhotoImportPortFake: VehiclePhotoImportPort {
    /// 空の画像データを返します。
    ///
    /// 責務: 画像取込要求を外部ファイルへアクセスせず完了します。
    /// - Parameter url: テストでは参照しない画像URL。
    /// - Returns: 空の画像データ。
    func importPhoto(at url: URL) async throws -> Data { Data() }
}
