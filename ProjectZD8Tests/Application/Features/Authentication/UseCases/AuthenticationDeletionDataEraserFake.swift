import Foundation
@testable import ProjectZD8

/// アカウント削除テストでデータ消去を記録します。
@MainActor
final class AuthenticationDeletionDataEraserFake: AccountDataErasurePort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: データ消去Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) {
        self.recorder = recorder
    }

    /// データ消去を共有履歴へ追加します。
    ///
    /// 責務: 1件のデータ消去を順序検証可能なイベントへ変換します。
    /// - Parameter userIdentifier: 消去対象のユーザー識別子。
    func eraseAllData(for userIdentifier: String) throws {
        recorder.events.append("erase:\(userIdentifier)")
    }
}
