@testable import ProjectZD8

/// 走行ルート記録設定の保存境界の fake です。読込・保存を記録し、保存を無視する振る舞いも選べます。
@MainActor
final class RouteRecordingPreferenceStoreFake: RouteRecordingPreferencePort {
    /// 現在保存されている値です。
    var isEnabled: Bool
    /// 保存要求を無視して保存値を変えない場合は `true` です。
    private let ignoresSave: Bool
    /// 読込回数です。
    private(set) var loadCount = 0
    /// 受け取った保存要求の値です(受信順)。
    private(set) var savedValues: [Bool] = []

    /// 初期値と保存の振る舞いを指定して生成します。
    ///
    /// 責務: テスト開始時の保存値と、保存要求を反映するかどうかを固定します。
    /// - Parameters:
    ///   - isEnabled: 初期の保存値。
    ///   - ignoresSave: 保存要求を記録だけして保存値を変えない場合は `true`。
    init(isEnabled: Bool, ignoresSave: Bool = false) {
        self.isEnabled = isEnabled
        self.ignoresSave = ignoresSave
    }

    /// 現在の保存値を返します。
    ///
    /// 責務: 読込回数を数えて保存値を返します。
    /// - Returns: 現在の保存値。
    func load() -> Bool {
        loadCount += 1
        return isEnabled
    }

    /// 値を保存します。
    ///
    /// 責務: 保存要求を記録し、無視する指定がなければ保存値を置き換えます。
    /// - Parameter isEnabled: 保存する値。
    func save(_ isEnabled: Bool) {
        savedValues.append(isEnabled)
        guard !ignoresSave else { return }
        self.isEnabled = isEnabled
    }
}
