import Foundation
import XCTest
@testable import ProjectZD8

/// 車両削除が関連セッションを全端末から先に除去することを検証します。
@MainActor
final class DeleteVehicleWithSessionsUseCaseTests: XCTestCase {
    /// 対象車両の終了済みセッションだけをCloudKit、ローカル、車両の順で削除します。
    ///
    /// 責務: 車両一括削除が別車両を保持して必要な副作用順序を満たすことを確認します。
    func testExecuteDeletesOnlyTargetVehicleSessionsBeforeVehicle() async throws {
        let targetVehicleID = VehicleID()
        let otherVehicleID = VehicleID()
        let first = endedSession(vehicleID: targetVehicleID)
        let second = endedSession(vehicleID: targetVehicleID)
        let other = endedSession(vehicleID: otherVehicleID)
        let dependencies = VehicleDeletionDependenciesSpy(sessions: [first, other, second])
        let useCase = makeUseCase(dependencies: dependencies)

        try await useCase.execute(vehicleID: targetVehicleID, accountIdentifier: "account")

        XCTAssertEqual(
            dependencies.events,
            [
                .cloud(first.id), .local(first.id),
                .cloud(second.id), .local(second.id),
                .vehicle(targetVehicleID)
            ]
        )
    }

    /// 取得中セッションがある車両は一部データを消さずに削除を拒否します。
    ///
    /// 責務: 車両一括削除が取得中セッション検出時に全副作用を開始前停止することを確認します。
    func testExecuteRejectsVehicleWithActiveSessionBeforeAnyDeletion() async {
        let vehicleID = VehicleID()
        let active = ConnectionSession(
            accountIdentifier: "account",
            vehicle: ConnectionSessionVehicle(id: vehicleID, name: "BRZ", displayIdentifier: "test")
        )
        let dependencies = VehicleDeletionDependenciesSpy(sessions: [active])
        let useCase = makeUseCase(dependencies: dependencies)

        do {
            try await useCase.execute(vehicleID: vehicleID, accountIdentifier: "account")
            XCTFail("取得中セッションを持つ車両は削除に失敗する必要があります")
        } catch {
            XCTAssertEqual(error as? DeleteVehicleWithSessionsUseCase.Error, .activeSession)
        }
        XCTAssertTrue(dependencies.events.isEmpty)
    }

    /// 指定車両を持つ終了済みテストセッションを生成します。
    ///
    /// 責務: 1件の車両IDを車両一括削除可能な終了済みセッションへ変換します。
    /// - Parameter vehicleID: セッションへ関連付ける車両ID。
    /// - Returns: ユーザー切断で終了したテストセッション。
    private func endedSession(vehicleID: VehicleID) -> ConnectionSession {
        var session = ConnectionSession(
            accountIdentifier: "account",
            vehicle: ConnectionSessionVehicle(id: vehicleID, name: "BRZ", displayIdentifier: "test")
        )
        session.endedAt = Date()
        session.endReason = .userDisconnected
        return session
    }

    /// 共通Spyを全永続化境界へ注入したテスト対象を生成します。
    ///
    /// 責務: 1件の副作用Spyを車両一括削除ユースケースの全境界へ結び付けます。
    /// - Parameter dependencies: セッションと車両の副作用を記録する共通Spy。
    /// - Returns: 削除順序を観測できる車両一括削除ユースケース。
    private func makeUseCase(dependencies: VehicleDeletionDependenciesSpy) -> DeleteVehicleWithSessionsUseCase {
        DeleteVehicleWithSessionsUseCase(
            sessionRepository: dependencies,
            localSessionErasureRepository: dependencies,
            sessionTransferRepository: dependencies,
            vehicleRepository: dependencies
        )
    }
}

/// 車両一括削除テストで観測する副作用です。
private enum VehicleDeletionEvent: Equatable {
    /// CloudKitへ公開したセッション削除です。
    case cloud(ConnectionSessionID)
    /// 現在端末で物理削除したセッションです。
    case local(ConnectionSessionID)
    /// 最後に削除した車両プロフィールです。
    case vehicle(VehicleID)
}

/// 車両一括削除に必要な全永続化境界を記録可能に置き換えます。
@MainActor
private final class VehicleDeletionDependenciesSpy: ConnectionSessionRepository, ConnectionSessionErasureRepository, ConnectionSessionTransferRepository, VehicleRepository {
    /// 履歴取得時に返す接続セッションです。
    private let storedSessions: [ConnectionSession]
    /// 発生順に記録した削除副作用です。
    private(set) var events: [VehicleDeletionEvent] = []

    /// 取得対象セッションを固定してSpyを生成します。
    ///
    /// 責務: セッション取得結果を車両削除副作用の記録先へ結び付けます。
    /// - Parameter sessions: 履歴取得時に返す接続セッション。
    init(sessions: [ConnectionSession]) { storedSessions = sessions }

    /// テスト対象外のセッション保存を副作用なしで受理します。
    ///
    /// 責務: 1件のセッション保存要求をテスト用の無操作として完了します。
    /// - Parameter session: 使用しない接続セッション。
    func save(_ session: ConnectionSession) throws {}

    /// 固定済み接続セッションを返します。
    ///
    /// 責務: 1件のアカウント履歴要求へ注入済みセッション一覧を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に固定した接続セッション一覧。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] { storedSessions }

    /// 現在端末のセッション削除を記録します。
    ///
    /// 責務: 1件のローカル削除要求を発生順イベントへ変換します。
    /// - Parameters:
    ///   - sessionID: 削除対象の接続セッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) throws {
        events.append(.local(sessionID))
    }

    /// テスト対象外の転送要求へ固定Digestを返します。
    ///
    /// 責務: 1件の転送要求を外部通信なしで完了します。
    /// - Parameters:
    ///   - package: 使用しない転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String { "digest" }

    /// テスト対象外の転送取得へ空配列を返します。
    ///
    /// 責務: 1件の転送取得要求を空結果として完了します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空の検証済み転送一覧。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] { [] }

    /// テスト対象外の受領証公開を副作用なしで受理します。
    ///
    /// 責務: 1件の受領証公開要求を外部通信なしで完了します。
    /// - Parameters:
    ///   - receipt: 使用しない受領証。
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMacReceipt(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// テスト対象外の受領証取得へ空配列を返します。
    ///
    /// 責務: 1件の受領証取得要求を空結果として完了します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空の受領証一覧。
    func downloadMacReceipts(for accountIdentifier: String) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// テスト対象外の削除マーカー取得へ空集合を返します。
    ///
    /// 責務: 1件の削除マーカー取得要求を空結果として完了します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空のセッションID集合。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> { [] }

    /// CloudKitセッション削除を記録します。
    ///
    /// 責務: 1件の全端末削除要求を発生順イベントへ変換します。
    /// - Parameters:
    ///   - sessionID: 削除対象の接続セッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {
        events.append(.cloud(sessionID))
    }

    /// テスト対象外のアカウント全削除を副作用なしで受理します。
    ///
    /// 責務: 1件のアカウント全削除要求を外部通信なしで完了します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {}

    /// テスト対象外の車両一覧取得へ空配列を返します。
    ///
    /// 責務: 1件の車両一覧要求を空結果として完了します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空の車両一覧。
    func loadVehicles(for accountIdentifier: String) async throws -> [VehicleProfile] { [] }

    /// テスト対象外の車両保存を副作用なしで受理します。
    ///
    /// 責務: 1件の車両保存要求を外部通信なしで完了します。
    /// - Parameters:
    ///   - vehicle: 使用しない車両プロフィール。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func saveVehicle(_ vehicle: VehicleProfile, for accountIdentifier: String) async throws {}

    /// 車両プロフィール削除を記録します。
    ///
    /// 責務: 1件の車両削除要求を発生順イベントへ変換します。
    /// - Parameters:
    ///   - id: 削除対象の車両ID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteVehicle(id: VehicleID, for accountIdentifier: String) async throws {
        events.append(.vehicle(id))
    }
}
