import Foundation
@testable import ProjectZD8

/// アカウント削除テストで資格情報削除を記録します。
@MainActor
final class AuthenticationDeletionSessionStoreFake: AuthenticationSessionStorePort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 資格情報削除Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) {
        self.recorder = recorder
    }

    /// このテストでは使用しない保存済み識別子を返します。
    ///
    /// 責務: 削除順序テストに不要な読込境界を未保存結果として満たします。
    /// - Returns: 常に `nil`。
    func loadUserIdentifier() throws -> String? { nil }

    /// このテストでは使用しない識別子保存を無視します。
    ///
    /// 責務: 削除順序テストに不要な保存境界を副作用なしで満たします。
    /// - Parameter _: 使用しないユーザー識別子。
    func saveUserIdentifier(_: String) throws {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// 資格情報削除を共有履歴へ追加します。
    ///
    /// 責務: 1件の資格情報削除を順序検証可能なイベントへ変換します。
    func removeUserIdentifier() throws {
        recorder.events.append("remove-session")
    }
}
