@testable import ProjectZD8

/// 位置情報の許可境界の fake です。現在の許可を差し替え、要求の呼出しを順に記録し、許可の変化を流せます。
@MainActor
final class LocationAuthorizationFake: LocationAuthorizationPort {
    /// 記録する許可要求の種類です。
    enum Request: Equatable {
        /// 「使用中のみ」の要求。
        case whenInUse
        /// 「常に許可」の要求。
        case always
    }

    /// 現在の許可状態です。テストが差し替えます。
    var currentPermission: LocationPermission
    /// 受け取った許可要求です(呼出し順)。
    private(set) var requests: [Request] = []
    /// `permissionChanges()` が呼ばれた回数です。
    private(set) var permissionChangesCallCount = 0
    /// 許可の変化の流れの送出口です(作成順)。
    private var continuations: [AsyncStream<LocationPermission>.Continuation] = []

    /// 初期の許可状態を指定して生成します。
    ///
    /// 責務: テスト開始時の許可状態を固定します。
    /// - Parameter currentPermission: 初期の許可状態。
    init(currentPermission: LocationPermission) {
        self.currentPermission = currentPermission
    }

    /// 許可状態の変化の流れを返します。
    ///
    /// 責務: 呼出回数を数え、`sendPermissionChange(_:)` で送出できる流れを返します。
    /// - Returns: 許可状態の流れ。
    func permissionChanges() -> AsyncStream<LocationPermission> {
        permissionChangesCallCount += 1
        let (stream, continuation) = AsyncStream.makeStream(of: LocationPermission.self)
        continuations.append(continuation)
        return stream
    }

    /// 「使用中のみ」の要求を記録します。
    ///
    /// 責務: 要求の種類を呼出し順に残します。
    func requestWhenInUseAuthorization() {
        requests.append(.whenInUse)
    }

    /// 「常に許可」の要求を記録します。
    ///
    /// 責務: 要求の種類を呼出し順に残します。
    func requestAlwaysAuthorization() {
        requests.append(.always)
    }

    /// 許可状態を変え、変化の流れへ流します。
    ///
    /// 責務: 現在の許可状態を置き換え、作られたすべての流れへ新しい状態を送出します。
    /// - Parameter permission: 新しい許可状態。
    func sendPermissionChange(_ permission: LocationPermission) {
        currentPermission = permission
        continuations.forEach { $0.yield(permission) }
    }

    /// 許可の変化の流れをすべて終えます。
    ///
    /// 責務: テストの後始末として、流れの消費者を確実に終わらせます。
    func finishAll() {
        continuations.forEach { $0.finish() }
    }
}
