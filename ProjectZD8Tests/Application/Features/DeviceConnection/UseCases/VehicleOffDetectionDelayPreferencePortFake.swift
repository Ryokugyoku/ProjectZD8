import Foundation
@testable import ProjectZD8

/// 保存値を持ち、呼び出しを記録する「エンジン停止とみなす時間」の保存ポートのフェイクです。
nonisolated final class VehicleOffDetectionDelayPreferencePortFake: VehicleOffDetectionDelayPreferencePort, @unchecked Sendable {
    /// 保存内容と記録を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した現在の保存値です。
    private var stored: VehicleOffDetectionDelay
    /// ロックで保護した保存された値の履歴です。
    private var savedValues: [VehicleOffDetectionDelay] = []
    /// ロックで保護した読み出しの回数です。
    private var storedLoadCount = 0

    /// 指定の保存値で生成します。
    ///
    /// 責務: 初期の保存値を持つフェイクを構築します。
    /// - Parameter initial: 最初に読める値。
    init(initial: VehicleOffDetectionDelay = .standard) {
        stored = initial
    }

    /// 保存された値の履歴です。
    var saved: [VehicleOffDetectionDelay] {
        lock.withLock { savedValues }
    }

    /// 読み出しの回数です。
    var loadCount: Int {
        lock.withLock { storedLoadCount }
    }

    /// 現在の保存値を返します。
    ///
    /// 責務: 読み出しを数えて保存値を返します。
    /// - Returns: 保存値。
    func load() -> VehicleOffDetectionDelay {
        lock.withLock {
            storedLoadCount += 1
            return stored
        }
    }

    /// 値を保存して履歴へ残します。
    ///
    /// 責務: 保存値を置き換え、履歴へ追加します。
    /// - Parameter delay: 保存する値。
    func save(_ delay: VehicleOffDetectionDelay) {
        lock.withLock {
            stored = delay
            savedValues.append(delay)
        }
    }
}
