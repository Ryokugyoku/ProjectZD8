/// 車両を特定できずに保存したログ(車両なし・観測VINなし)の一覧を読み込みます。
struct LoadVehicleUnknownConnectionSessionsUseCase {
    /// 車両不明ログの保存先です。
    private let repository: any VehicleUnknownConnectionSessionRepository

    /// 保存先を固定して生成します。
    ///
    /// 責務: 車両不明ログの照会先を結び付けます。
    /// - Parameter repository: 車両不明ログの保存先。
    init(repository: any VehicleUnknownConnectionSessionRepository) {
        self.repository = repository
    }

    /// 指定アカウントの車両不明ログを新しい順で返します。
    ///
    /// 責務: 保存先の照会結果をそのまま返し、失敗は呼び出し元へ伝えます(空の一覧に潰しません)。
    /// - Parameter accountIdentifier: 対象のAppleアカウント識別子。
    /// - Returns: 車両不明ログ。
    /// - Throws: 保存先の照会失敗。
    func execute(accountIdentifier: String) throws -> [ConnectionSession] {
        try repository.vehicleUnknownSessions(for: accountIdentifier)
    }
}
