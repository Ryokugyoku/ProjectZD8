/// 設定・許可・前面かどうか・取得可否から、位置を取得するかと残す状態の種類を決める純粋な判定です。
///
/// 上から順に評価します: 非対応のプラットフォーム → 設定オフ → 許可が未確定・拒否・制限 →
/// 「使用中のみ」で背面 → 取得不可 → 概略の位置のみ → 記録中。
nonisolated struct SessionLocationRecordingPolicy: Sendable {
    /// 判定器を生成します。
    ///
    /// 責務: 状態を持たない判定器を作ります。
    init() {}

    /// 位置記録の判定結果を返します。
    ///
    /// 責務: 記録に関わる4つの入力を、取得の要否と状態の種類の組へ変換します。
    /// - Parameters:
    ///   - isRecordingEnabled: 利用者の設定で記録がオンなら `true`。
    ///   - permission: 現在の位置情報の許可状態。
    ///   - isForeground: アプリが前面なら `true`。
    ///   - isLocationAvailable: 位置を取得できている(取得不可の通知を受けていない)なら `true`。
    /// - Returns: 取得の要否と残す状態の種類。
    func decision(
        isRecordingEnabled: Bool,
        permission: LocationPermission,
        isForeground: Bool,
        isLocationAvailable: Bool
    ) -> SessionLocationRecordingDecision {
        if permission.level == .unsupportedPlatform {
            return Self.notAcquiring(.unsupportedPlatform)
        }
        guard isRecordingEnabled else {
            return Self.notAcquiring(.disabledBySetting)
        }
        if let blockedKind = Self.blockedEventKind(for: permission.level) {
            return Self.notAcquiring(blockedKind)
        }
        if permission.level == .whenInUse && !isForeground {
            return Self.notAcquiring(.backgroundWithoutAlwaysAuthorization)
        }
        return SessionLocationRecordingDecision(
            acquiresLocation: true,
            eventKind: Self.acquiringEventKind(permission: permission, isLocationAvailable: isLocationAvailable)
        )
    }

    /// 許可が無いために取得しない場合の状態の種類を返します。
    ///
    /// 責務: 許可の段階のうち、取得を妨げるもの(未確定・拒否・制限)を対応する状態の種類へ変換します。
    /// - Parameter level: 許可の段階。
    /// - Returns: 取得を妨げる段階なら状態の種類。それ以外は `nil`。
    private static func blockedEventKind(for level: LocationAuthorizationLevel) -> ConnectionSessionLocationEventKind? {
        switch level {
        case .notDetermined: .authorizationNotDetermined
        case .denied: .authorizationDenied
        case .restricted: .authorizationRestricted
        case .whenInUse, .always, .unsupportedPlatform: nil
        }
    }

    /// 取得する場合の状態の種類を返します。
    ///
    /// 責務: 取得可否と精度の許可を、取得中の状態の種類へ変換します(取得不可を概略の位置より優先します)。
    /// - Parameters:
    ///   - permission: 現在の位置情報の許可状態。
    ///   - isLocationAvailable: 位置を取得できているなら `true`。
    /// - Returns: 取得中の状態の種類。
    private static func acquiringEventKind(
        permission: LocationPermission,
        isLocationAvailable: Bool
    ) -> ConnectionSessionLocationEventKind {
        guard isLocationAvailable else { return .locationUnavailable }
        return permission.isPreciseAccuracy ? .recording : .recordingWithReducedAccuracy
    }

    /// 取得しない判定を作ります。
    ///
    /// 責務: 状態の種類を、取得しない判定結果へ包みます。
    /// - Parameter kind: 残す状態の種類。
    /// - Returns: 取得しない判定結果。
    private static func notAcquiring(_ kind: ConnectionSessionLocationEventKind) -> SessionLocationRecordingDecision {
        SessionLocationRecordingDecision(acquiresLocation: false, eventKind: kind)
    }
}
