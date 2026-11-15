@testable import ProjectZD8

/// 保存要求を受け取っても保存値を変えない自動記録設定の保存境界です。表示が保存後の読み直し値に従うかを確かめます。
@MainActor
final class AutomaticRecordingPreferenceSaveIgnoringStub: AutomaticRecordingPreferencePort {
    /// 常に返す保存値です。
    private let storedValue: Bool
    /// 受け取った保存要求です(受信順)。
    private(set) var requestedValues: [Bool] = []

    /// 常に返す保存値を指定して生成します。
    ///
    /// 責務: 保存要求に関係なく読込が返す値を固定します。
    /// - Parameter storedValue: 読込が返す値。
    init(storedValue: Bool) {
        self.storedValue = storedValue
    }

    /// 固定の保存値を返します。
    ///
    /// 責務: 保存要求の有無に関係なく同じ値を返します。
    /// - Returns: 初期化時の値。
    func load() -> Bool {
        storedValue
    }

    /// 保存要求を記録だけして捨てます。
    ///
    /// 責務: 要求値を記録し、保存値は変えません。
    /// - Parameter isEnabled: 要求された値。
    func save(_ isEnabled: Bool) {
        requestedValues.append(isEnabled)
    }
}
