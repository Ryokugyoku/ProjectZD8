/// 観測したVINに一致する登録済み車両を、サインイン中アカウントの車両一覧から探します。
@MainActor
struct FindRegisteredVehicleByVINUseCase {
    /// アカウント単位の車両保存先です。
    private let repository: any VehicleRepository

    /// 車両保存先を固定して生成します。
    ///
    /// 責務: 照合に使う車両一覧の読込元を固定します。
    /// - Parameter repository: アカウント単位の車両保存先。
    init(repository: any VehicleRepository) {
        self.repository = repository
    }

    /// VINに一致する登録済み車両を返します。
    ///
    /// 責務: 前後の空白を除いたVINを大文字小文字を区別せずに登録済み車両のVINと比べます。
    /// - Parameters:
    ///   - vin: 観測したVIN。`nil` や空白だけの場合は照合しません。
    ///   - accountIdentifier: サインイン中アカウントの識別子。`nil` や空の場合は照合しません。
    /// - Returns: 一致した最初の車両(保存先の並び順)。照合しない場合と一致しない場合は `nil`。
    /// - Throws: 車両一覧を読み込めなかった場合の保存先エラー。
    func execute(vin: String?, accountIdentifier: String?) async throws -> VehicleProfile? {
        guard let normalizedVIN = Self.comparableVIN(vin),
              let accountIdentifier, !accountIdentifier.isEmpty else { return nil }
        let vehicles = try await repository.loadVehicles(for: accountIdentifier)
        return vehicles.first { Self.comparableVIN($0.vin) == normalizedVIN }
    }

    /// 比較用にVINを正規化します。
    ///
    /// 責務: 前後の空白を除いて大文字へ揃え、空なら比較対象外にします。
    /// - Parameter vin: 正規化するVIN。
    /// - Returns: 正規化したVIN。`nil` や空白だけの場合は `nil`。
    static func comparableVIN(_ vin: String?) -> String? {
        ConnectionSession.normalizedObservedVIN(vin)?.uppercased()
    }
}
