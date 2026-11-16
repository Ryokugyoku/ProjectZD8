import Foundation
@testable import ProjectZD8

/// アカウント削除テストで車両カタログ削除を記録します。
@MainActor
final class AuthenticationDeletionVehicleDataEraserFake: AccountVehicleDataErasurePort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 車両カタログ削除Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) { self.recorder = recorder }

    /// 全保存先の車両カタログ削除を共有履歴へ追加します。
    ///
    /// 責務: 1件の車両データ全削除を順序検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {
        recorder.events.append("delete-vehicle-data:\(accountIdentifier)")
    }

    /// このテストでは端末キャッシュに車両を保持しません。
    ///
    /// 責務: テスト対象外のローカル車両ID照会へ空配列を返します。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func localVehicleIDs(for _: String) -> [VehicleID] { [] }

    /// このテストでは端末キャッシュ単独削除を使用しません。
    ///
    /// 責務: テスト対象外の車両キャッシュ削除要求を副作用なしで満たします。
    /// - Parameter _: 使用しないアカウント識別子。
    func removeLocalVehicleCache(for _: String) {
        // このテストでは呼び出しを観測しないため、何もしない。
    }
}
