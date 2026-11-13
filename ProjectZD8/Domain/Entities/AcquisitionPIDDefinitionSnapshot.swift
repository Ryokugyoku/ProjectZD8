/// 取得開始時点で確認されたPID対応状態です。
nonisolated enum AcquisitionPIDCapabilitySupport: String, Equatable, Sendable {
    /// 応答などの証拠により対応が確認されています。
    case supported
    /// protocol上の明示的証拠により非対応が確認されています。
    case unsupported
    /// 未探索、曖昧な応答、または探索失敗により判定できません。
    case indeterminate
}

/// 1件のPIDについて取得時点の変換意味と能力選択を固定します。
nonisolated struct AcquisitionPIDDefinitionSnapshot: Equatable, Sendable {
    /// 定義を結び付けるService/PIDです。
    let request: OBDPIDRequest
    /// 取得時に確認された対応状態です。`nil` はlegacy欠落を表します。
    let capabilitySupport: AcquisitionPIDCapabilitySupport?
    /// 今回の継続収集対象かどうかです。`nil` はlegacy欠落を表します。
    let isCollectionEnabled: Bool?
    /// 取得時PID定義のrevisionです。`nil` は推測禁止のlegacy欠落を表します。
    let definitionRevision: Int?
    /// 式評価に必要なbyte数です。`nil` は取得時証拠の欠落を表します。
    let requiredByteCount: Int?
    /// 再構築可能な取得時式identityです。`nil` は取得時証拠の欠落を表します。
    let definitionIdentity: AcquisitionPIDDefinitionIdentity?
    /// 取得時の単位です。`nil` は取得時証拠の欠落を表します。
    let unit: String?
    /// 取得時の有効範囲です。`nil` は範囲metadata自体の欠落を表します。
    let validityRange: AcquisitionPIDValidityRange?

    /// 取得時PID定義snapshotを生成します。
    ///
    /// 責務: 1件のService/PIDに対する取得時の能力、選択、変換契約を不変値へ固定します。
    /// - Parameters:
    ///   - request: 定義を結び付けるService/PID。
    ///   - capabilitySupport: 証拠に基づく対応状態、またはlegacy欠落を示す `nil`。
    ///   - isCollectionEnabled: 今回の収集選択、またはlegacy欠落を示す `nil`。
    ///   - definitionRevision: 正の取得時revision、またはlegacy欠落を示す `nil`。
    ///   - requiredByteCount: 正の必要byte数、または取得時証拠欠落を示す `nil`。
    ///   - definitionIdentity: 再構築可能な取得時式identity、または取得時証拠欠落を示す `nil`。
    ///   - unit: 取得時の単位、または取得時証拠欠落を示す `nil`。
    ///   - validityRange: 取得時の明示範囲、範囲なし、またはmetadata欠落を示す `nil`。
    /// - Throws: revisionまたは必要byte数が正でない場合は `AcquisitionPIDDefinitionSnapshotError.invalidNumericContract`。
    init(
        request: OBDPIDRequest,
        capabilitySupport: AcquisitionPIDCapabilitySupport?,
        isCollectionEnabled: Bool?,
        definitionRevision: Int?,
        requiredByteCount: Int?,
        definitionIdentity: AcquisitionPIDDefinitionIdentity?,
        unit: String?,
        validityRange: AcquisitionPIDValidityRange?
    ) throws {
        guard definitionRevision.map({ $0 > 0 }) ?? true,
              requiredByteCount.map({ $0 > 0 }) ?? true else {
            throw AcquisitionPIDDefinitionSnapshotError.invalidNumericContract
        }
        self.request = request
        self.capabilitySupport = capabilitySupport
        self.isCollectionEnabled = isCollectionEnabled
        self.definitionRevision = definitionRevision
        self.requiredByteCount = requiredByteCount
        self.definitionIdentity = definitionIdentity
        self.unit = unit
        self.validityRange = validityRange
    }
}

/// PID定義snapshotを確定できない理由です。
nonisolated enum AcquisitionPIDDefinitionSnapshotError: Error, Equatable, Sendable {
    /// revisionまたは必要byte数が正ではありません。
    case invalidNumericContract
}
