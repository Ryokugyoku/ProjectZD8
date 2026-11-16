import Foundation
@testable import ProjectZD8

/// アカウント削除テストで整備カタログ削除を記録します。
@MainActor
final class AuthenticationDeletionMaintenanceDataEraserFake: AccountMaintenanceDataErasurePort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 整備カタログ削除Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) { self.recorder = recorder }

    /// 整備カタログ削除を共有履歴へ追加します。
    ///
    /// 責務: 1件の整備データ全削除を順序検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllMaintenanceData(for accountIdentifier: String) async throws {
        recorder.events.append("delete-maintenance-data:\(accountIdentifier)")
    }
}
