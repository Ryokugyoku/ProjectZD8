import Foundation
@testable import ProjectZD8

/// アカウント削除テストで失効発行を記録します。
@MainActor
final class AuthenticationDeletionRevocationPortFake: AccountSessionRevocationPort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 失効発行Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) {
        self.recorder = recorder
    }

    /// このテストでは使用しないセッション基準登録を無視します。
    ///
    /// 責務: 削除順序テストに不要な基準登録境界を副作用なしで満たします。
    /// - Parameter _: 使用しないユーザー識別子。
    func registerCurrentSession(for _: String) {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// 失効発行を共有履歴へ追加します。
    ///
    /// 責務: 1件の失効発行を順序検証可能なイベントへ変換します。
    /// - Parameter userIdentifier: 失効対象のユーザー識別子。
    func publishRevocation(for userIdentifier: String) {
        recorder.events.append("publish:\(userIdentifier)")
    }

    /// このテストでは使用しない失効監視を無視します。
    ///
    /// 責務: 削除順序テストに不要な監視境界を副作用なしで満たします。
    /// - Parameters:
    ///   - _: 使用しないユーザー識別子。
    ///   - _: 使用しない失効受信処理。
    func startObserving(
        for _: String,
        receive _: @escaping () -> Void
    ) {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// このテストでは使用しない監視終了を無視します。
    ///
    /// 責務: 削除順序テストに不要な監視終了境界を副作用なしで満たします。
    func stopObserving() {
        // このテストでは呼び出しを観測しないため、何もしない。
    }
}
