import Foundation

/// 1件のPIDについてmanifestへ固定する能力と収集選択のApplication入力です。
nonisolated struct ConnectionSessionAcquisitionPIDCapabilityInput: Equatable, Sendable {
    /// 能力証拠を結び付けるService/PIDです。
    let request: OBDPIDRequest
    /// 明示証拠に基づく対応状態です。
    let support: AcquisitionPIDCapabilitySupport
    /// 対応状態とは独立した今回の収集選択です。
    let isCollectionEnabled: Bool

    /// PID能力と収集選択を明示入力として固定します。
    ///
    /// 責務: 1件のService/PIDについて対応状態と収集選択を別軸で保持します。
    /// - Parameters:
    ///   - request: 能力証拠を結び付けるService/PID。
    ///   - support: `supported`、`unsupported`、`indeterminate`の明示状態。
    ///   - isCollectionEnabled: 今回の収集選択。
    init(
        request: OBDPIDRequest,
        support: AcquisitionPIDCapabilitySupport,
        isCollectionEnabled: Bool
    ) {
        self.request = request
        self.support = support
        self.isCollectionEnabled = isCollectionEnabled
    }

    /// 未登録車両で、ECUが対応PIDビットマップで対応を返した標準PIDの証跡を生成します。
    ///
    /// 責務: 対応はECUの応答に基づく `supported`、収集選択は車両別トグルが存在しないため常に有効として固定します。
    /// 未登録車両であることはセッションの車両が `nil` であることで表され、この証跡は推測した値を含みません。
    /// - Parameter request: ECUが対応を返したService/PID。
    /// - Returns: 未登録車両の標準PIDのcapability証跡。
    static func unregisteredVehicleSupported(_ request: OBDPIDRequest) -> ConnectionSessionAcquisitionPIDCapabilityInput {
        ConnectionSessionAcquisitionPIDCapabilityInput(request: request, support: .supported, isCollectionEnabled: true)
    }
}
