@testable import ProjectZD8

/// 自動記録設定の保存境界の fake です。テストが値を差し替え、読込・保存を記録します。
@MainActor
final class AutomaticRecordingPreferenceFake: AutomaticRecordingPreferencePort {
    /// 現在保存されている値です。
    var isEnabled: Bool

    /// 読込回数です。
    private(set) var loadCount = 0

    /// 保存された値です(保存順)。
    private(set) var savedValues: [Bool] = []

    /// 初期値を指定して生成します。
    ///
    /// 責務: テスト開始時の自動記録設定を固定します。
    /// - Parameter isEnabled: 初期値。
    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// 現在の値を返します。
    ///
    /// 責務: 読込回数を数えて現在の値を返します。
    /// - Returns: 現在の値。
    func load() -> Bool {
        loadCount += 1
        return isEnabled
    }

    /// 値を保存します。
    ///
    /// 責務: 保存された値を記録し、現在の値を置き換えます。
    /// - Parameter isEnabled: 保存する値。
    func save(_ isEnabled: Bool) {
        savedValues.append(isEnabled)
        self.isEnabled = isEnabled
    }
}
