import Foundation
@testable import ProjectZD8

/// 車両別対応PIDをメモリに保持し、読込と書込の呼び出しをすべて記録するRepositoryのフェイクです。
final class VehiclePIDCapabilityRepositorySpy: VehiclePIDCapabilityRepository, @unchecked Sendable {
    /// 記録への並行アクセスを直列化します。
    private let lock = NSLock()
    /// 車両IDごとの保存済み対応PIDです。
    private var stored: [VehicleID: [VehiclePIDCapability]]
    /// 読込に使われた車両IDの記録です。
    private var readLog: [VehicleID] = []
    /// 初回保存の記録です。
    private var insertLog: [[VehiclePIDCapability]] = []
    /// 追加保存の記録です。
    private var mergeLog: [[VehiclePIDCapability]] = []
    /// 収集選択更新の回数です。
    private var collectionUpdateCount = 0

    /// 初期保存内容を指定して生成します。
    ///
    /// 責務: テスト開始時点の車両別対応PIDを固定します。
    /// - Parameter stored: 車両IDごとの保存済み対応PID。
    init(stored: [VehicleID: [VehiclePIDCapability]] = [:]) { self.stored = stored }

    /// 読込に使われた車両IDの一覧です。
    var readVehicleIDs: [VehicleID] { locked { readLog } }
    /// 初回保存された対応PIDの一覧です。
    var insertedInitial: [[VehiclePIDCapability]] { locked { insertLog } }
    /// 追加保存された対応PIDの一覧です。
    var merged: [[VehiclePIDCapability]] { locked { mergeLog } }
    /// 読込・書込・選択更新を合わせた呼び出し総数です。
    var totalCallCount: Int { locked { readLog.count + insertLog.count + mergeLog.count + collectionUpdateCount } }

    /// 保存済み対応PIDを返し、読込を記録します。
    ///
    /// 責務: 1件の車両IDの読込を記録して保存内容を返します。
    /// - Parameter vehicleID: 読込対象の車両ID。
    /// - Returns: 保存済み対応PID。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability] {
        locked {
            readLog.append(vehicleID)
            return stored[vehicleID] ?? []
        }
    }

    /// 初回探索結果を保存し、記録します。
    ///
    /// 責務: 初回保存を記録して保存内容を置き換えます。
    /// - Parameters:
    ///   - capabilities: 保存する対応PID。
    ///   - vehicleID: 保存先の車両ID。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {
        locked {
            insertLog.append(capabilities)
            stored[vehicleID] = capabilities
        }
    }

    /// 追加探索結果を既存内容へ足し、記録します。
    ///
    /// 責務: 追加保存を記録して未保存の対応PIDだけを追記します。
    /// - Parameters:
    ///   - capabilities: 追加する対応PID。
    ///   - vehicleID: 保存先の車両ID。
    func mergeDiscovered(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {
        locked {
            mergeLog.append(capabilities)
            var current = stored[vehicleID] ?? []
            for capability in capabilities where !current.contains(where: { $0.id == capability.id }) {
                current.append(capability)
            }
            stored[vehicleID] = current
        }
    }

    /// 収集選択更新を記録します。
    ///
    /// 責務: 想定外の選択更新を回数として検出できるようにします。
    /// - Parameters:
    ///   - isEnabled: 使用しない選択状態。
    ///   - request: 使用しないPID。
    ///   - vehicleID: 使用しない車両ID。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) throws {
        locked { collectionUpdateCount += 1 }
    }

    /// ロック下で処理を実行します。
    ///
    /// 責務: 記録の読み書きを1つの臨界区間へまとめます。
    /// - Parameter body: 実行する処理。
    /// - Returns: 処理の戻り値。
    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
