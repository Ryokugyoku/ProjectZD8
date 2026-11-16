import Foundation
@testable import ProjectZD8

/// 端末キャッシュの車両IDを設定でき、キャッシュ削除を共有履歴へ載せる車両削除Fakeです。
@MainActor
final class DeleteAccountUseCaseCachedVehicleEraserFake: AccountVehicleDataErasurePort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 端末キャッシュにあるものとして返す車両IDです。
    var cachedVehicleIDs: [VehicleID]

    /// 共有記録先と端末キャッシュの内容を注入します。
    ///
    /// 責務: 車両削除Fakeを記録先と初期のキャッシュ内容へ結び付けます。
    /// - Parameters:
    ///   - recorder: 副作用名を発生順に保持する記録先。
    ///   - cachedVehicleIDs: 端末キャッシュにある車両ID群。
    init(recorder: DeleteAccountUseCaseRecorder, cachedVehicleIDs: [VehicleID] = []) {
        self.recorder = recorder
        self.cachedVehicleIDs = cachedVehicleIDs
    }

    /// CloudKit車両カタログ削除を履歴へ追加します。
    ///
    /// 責務: 1件の車両クラウド削除を検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {
        try recorder.record("delete-vehicle-data:\(accountIdentifier)")
    }

    /// 設定された端末キャッシュの車両IDを返します。
    ///
    /// 責務: 控えとの合成を検証できるよう、現在のキャッシュ内容を返します。
    /// - Parameter accountIdentifier: 照会対象のアカウント識別子。
    /// - Returns: 端末キャッシュにある車両ID群。
    func localVehicleIDs(for accountIdentifier: String) -> [VehicleID] { cachedVehicleIDs }

    /// 端末内車両キャッシュ削除を履歴へ追加します。
    ///
    /// 責務: 1件のキャッシュ削除を記録し、以後のキャッシュを空にします。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String) {
        try? recorder.record("remove-local-vehicle-cache:\(accountIdentifier)")
        cachedVehicleIDs = []
    }
}

/// 整備のクラウド削除を共有履歴へ載せるFakeです。
@MainActor
final class DeleteAccountUseCaseRecordingMaintenanceFake: AccountMaintenanceDataErasurePort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 整備削除Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// 整備クラウド削除を履歴へ追加します。
    ///
    /// 責務: 1件の整備クラウド削除を検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllMaintenanceData(for accountIdentifier: String) async throws {
        try recorder.record("delete-maintenance-data:\(accountIdentifier)")
    }
}

/// ローカル消去へ渡された車両IDを記録するデータ消去Fakeです。
@MainActor
final class DeleteAccountUseCaseKnownIDsDataEraserFake: AccountDataErasurePort {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// `eraseAllData(for:knownVehicleIDs:)` に渡された車両IDの呼び出しごとの履歴です。
    private(set) var receivedVehicleIDs: [[VehicleID]] = []

    /// 車両IDなしの `eraseAllData(for:)` が呼ばれた回数です。
    private(set) var plainEraseCount = 0

    /// 共有記録先を注入します。
    ///
    /// 責務: データ消去Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// 車両IDなしの消去を記録します。
    ///
    /// 責務: 車両IDを渡さない経路が使われたことを数えます。
    /// - Parameter userIdentifier: 消去対象のユーザー識別子。
    func eraseAllData(for userIdentifier: String) throws {
        plainEraseCount += 1
        try recorder.record("erase:\(userIdentifier)")
    }

    /// 車両ID付きの消去を記録します。
    ///
    /// 責務: 渡された車両IDを履歴へ追加し、消去を履歴へ追加します。
    /// - Parameters:
    ///   - userIdentifier: 消去対象のユーザー識別子。
    ///   - vehicleIDs: 車両別設定の消去に使う車両ID群。
    func eraseAllData(for userIdentifier: String, knownVehicleIDs vehicleIDs: [VehicleID]) throws {
        receivedVehicleIDs.append(vehicleIDs)
        try recorder.record("erase:\(userIdentifier)")
    }
}

/// 車両IDの控えをメモリ上で保持し、操作を共有履歴へ載せるFakeです。
@MainActor
final class AccountDeletionVehicleIDStoreFake: AccountDeletionVehicleIDStorePort {
    /// アカウントごとの控えです。
    private(set) var stored: [String: [VehicleID]] = [:]

    /// 保存の要求ごとの内容です。
    private(set) var saveCalls: [(account: String, ids: [VehicleID])] = []

    /// 共有記録先です。使わないテストでは `nil` です。
    private let recorder: DeleteAccountUseCaseRecorder?

    /// 共有記録先と初期の控えを指定して生成します。
    ///
    /// 責務: 控えの保存・削除を他の副作用と同じ順序の履歴へ載せられるようにします。
    /// - Parameters:
    ///   - recorder: 副作用名を発生順に保持する記録先。
    ///   - initial: 初期の控え。
    init(recorder: DeleteAccountUseCaseRecorder? = nil, initial: [String: [VehicleID]] = [:]) {
        self.recorder = recorder
        stored = initial
    }

    /// 控えを返します。
    ///
    /// 責務: 指定アカウントの控えを返し、無ければ空配列を返します。
    /// - Parameter accountIdentifier: 対象アカウント識別子。
    /// - Returns: 控えた車両ID群。
    func pendingVehicleIDs(for accountIdentifier: String) -> [VehicleID] {
        stored[accountIdentifier] ?? []
    }

    /// 控えを置き換えて保存します。
    ///
    /// 責務: 保存の要求を記録し、控えを置き換えます。
    /// - Parameters:
    ///   - vehicleIDs: 控える車両ID群。
    ///   - accountIdentifier: 対象アカウント識別子。
    func savePendingVehicleIDs(_ vehicleIDs: [VehicleID], for accountIdentifier: String) {
        try? recorder?.record("save-pending-vehicle-ids:\(accountIdentifier)")
        saveCalls.append((accountIdentifier, vehicleIDs))
        stored[accountIdentifier] = vehicleIDs
    }

    /// 控えを消します。
    ///
    /// 責務: 削除の要求を記録し、指定アカウントの控えを取り除きます。
    /// - Parameter accountIdentifier: 対象アカウント識別子。
    func clearPendingVehicleIDs(for accountIdentifier: String) {
        try? recorder?.record("clear-pending-vehicle-ids:\(accountIdentifier)")
        stored[accountIdentifier] = nil
    }
}
