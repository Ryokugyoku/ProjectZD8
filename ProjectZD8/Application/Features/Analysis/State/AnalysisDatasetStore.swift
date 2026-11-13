import Foundation
import Synchronization

/// 符号化済みの分析データを、Webワークベンチが取得できる相対パスで保持します。
///
/// ホスト側のスキームハンドラ(任意のスレッド)から読むため、内部をロックで保護します。
nonisolated final class AnalysisDatasetStore: Sendable {
    private let storage = Mutex<[String: Data]>([:])

    /// 空のストアを生成します。
    ///
    /// 責務: 分析データの置き場を初期化します。
    init() {}

    /// 責務: データを指定パスへ保存(置換)します。
    func set(_ data: Data, forPath path: String) {
        storage.withLock { $0[path] = data }
    }

    /// 責務: 指定パスのデータを返します。無ければ `nil` です。
    func data(forPath path: String) -> Data? {
        storage.withLock { $0[path] }
    }

    /// 責務: 指定パスのデータを破棄します。
    func remove(path: String) {
        storage.withLock { _ = $0.removeValue(forKey: path) }
    }

    /// 責務: データセットのパスを組み立てます。
    static func datasetPath(for id: SessionID) -> String { "dataset/\(id.rawValue.uuidString).json" }

    /// 責務: 長期傾向のパスを組み立てます。
    static func trendPath(for id: VehicleID) -> String { "trend/\(id.rawValue.uuidString).json" }
}
