/// 車両未登録のまま観測VIN付きで記録した接続セッションを照会します。
struct LoadUnassignedObservedVINConnectionSessionsUseCase {
    /// 観測VIN付きセッションの照会境界です。
    private let repository: any ObservedVINConnectionSessionRepository

    /// 観測VIN付きセッションの照会境界を固定します。
    ///
    /// 責務: 未紐付けセッション照会に使う永続化境界を保持します。
    /// - Parameter repository: 観測VIN付きセッションの照会境界。
    init(repository: any ObservedVINConnectionSessionRepository) {
        self.repository = repository
    }

    /// 指定アカウントで車両未設定かつ観測VINを持つセッションを返します。
    ///
    /// 責務: 1件のアカウントを未紐付けの観測VIN付きセッション一覧へ変換します。
    /// - Parameter accountIdentifier: 照会対象のAppleアカウント識別子。
    /// - Returns: 車両未設定かつ観測VINを持つセッション。保存先が返す開始日時の新しい順。
    /// - Throws: 保存先を利用できない、または保存値が不正な場合のエラー。空配列へは変換しません。
    func execute(accountIdentifier: String) throws -> [ConnectionSession] {
        try repository.unassignedSessionsWithObservedVIN(for: accountIdentifier)
    }
}
