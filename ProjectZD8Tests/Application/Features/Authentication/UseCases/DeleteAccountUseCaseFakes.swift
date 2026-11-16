import Foundation
@testable import ProjectZD8

/// アカウント削除ユースケースの副作用順序を記録し、指定した段階を失敗させます。
@MainActor
final class DeleteAccountUseCaseRecorder {
    /// 発生順に保存したテスト用副作用名です(`段階名:ユーザー識別子` 形式)。
    private(set) var events: [String] = []

    /// 失敗させる段階名(`:` より前)と、その時に投げるエラーです。
    var failures: [String: Error] = [:]

    /// 副作用を記録し、その段階が失敗指定なら記録後に投げます。
    ///
    /// 責務: 1件の副作用を発生順の履歴へ追加し、指定された段階だけを失敗させます。
    /// - Parameter event: `段階名:ユーザー識別子` 形式の副作用名。
    /// - Throws: 段階が失敗指定の場合のエラー。
    func record(_ event: String) throws {
        events.append(event)
        let step = event.split(separator: ":", maxSplits: 1).first.map(String.init) ?? event
        if let error = failures[step] { throw error }
    }

    /// 段階名の最初の出現位置を返します。
    ///
    /// 責務: 順序検証のために履歴から1件の段階の位置を引きます。
    /// - Parameter step: `:` より前の段階名。
    /// - Returns: 最初に現れた位置。無ければ `nil`。
    func index(of step: String) -> Int? {
        events.firstIndex { $0.hasPrefix(step + ":") || $0 == step }
    }
}

/// アカウント削除テストで失効発行を記録します。
@MainActor
final class DeleteAccountUseCaseRevocationFake: AccountSessionRevocationPort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 失効発行Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// 使用しない基準登録を無視します。
    ///
    /// 責務: 削除テストに不要な境界を副作用なしで満たします。
    /// - Parameter userIdentifier: 使用しないユーザー識別子。
    func registerCurrentSession(for _: String) {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// 失効発行を履歴へ追加します。
    ///
    /// 責務: 1件の失効発行を検証可能なイベントへ変換します。
    /// - Parameter userIdentifier: 失効対象のユーザー識別子。
    func publishRevocation(for userIdentifier: String) {
        try? recorder.record("publish:\(userIdentifier)")
    }

    /// 使用しない失効監視を無視します。
    ///
    /// 責務: 削除テストに不要な監視境界を副作用なしで満たします。
    /// - Parameters:
    ///   - userIdentifier: 使用しないユーザー識別子。
    ///   - receive: 使用しない失効受信処理。
    func startObserving(for _: String, receive _: @escaping () -> Void) {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// 使用しない監視終了を無視します。
    ///
    /// 責務: 削除テストに不要な監視終了境界を副作用なしで満たします。
    func stopObserving() {
        // このテストでは呼び出しを観測しないため、何もしない。
    }
}

/// アカウント削除テストでローカルデータ消去を記録します。
@MainActor
final class DeleteAccountUseCaseDataEraserFake: AccountDataErasurePort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: データ消去Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// ローカル消去を履歴へ追加します。
    ///
    /// 責務: 1件のローカル消去を検証可能なイベントへ変換します。
    /// - Parameter userIdentifier: 消去対象のユーザー識別子。
    func eraseAllData(for userIdentifier: String) throws {
        try recorder.record("erase:\(userIdentifier)")
    }
}

/// アカウント削除テストで車両カタログのCloudKit削除と端末キャッシュ削除を記録します。
@MainActor
final class DeleteAccountUseCaseVehicleEraserFake: AccountVehicleDataErasurePort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 車両削除Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// CloudKit車両カタログ削除を履歴へ追加します。
    ///
    /// 責務: 1件の車両クラウド削除を検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {
        try recorder.record("delete-vehicle-data:\(accountIdentifier)")
    }

    /// 使用しない端末内車両ID照会へ空配列を返します。
    ///
    /// 責務: 削除テストに不要な照会境界を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func localVehicleIDs(for _: String) -> [VehicleID] { [] }

    /// 端末内車両キャッシュ削除を履歴へ追加します。
    ///
    /// 責務: 1件のキャッシュ削除を検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String) {
        try? recorder.record("remove-local-vehicle-cache:\(accountIdentifier)")
    }
}

/// アカウント削除テストで資格情報削除を記録します。
@MainActor
final class DeleteAccountUseCaseSessionStoreFake: AuthenticationSessionStorePort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 資格情報削除Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// 使用しない読込を未保存として返します。
    ///
    /// 責務: 削除テストに不要な読込境界を満たします。
    /// - Returns: 常に `nil`。
    func loadUserIdentifier() throws -> String? { nil }

    /// 使用しない保存を無視します。
    ///
    /// 責務: 削除テストに不要な保存境界を満たします。
    /// - Parameter userIdentifier: 使用しないユーザー識別子。
    func saveUserIdentifier(_: String) throws {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// 資格情報削除を履歴へ追加します。
    ///
    /// 責務: 1件の資格情報削除を検証可能なイベントへ変換します。
    func removeUserIdentifier() throws {
        try recorder.record("remove-session:")
    }
}
