import Foundation

/// session取得manifestを作成する決定済みApplication入力です。
nonisolated struct CreateConnectionSessionAcquisitionManifestInput: Sendable {
    /// manifestを所有するsession識別子です。
    let sessionID: ConnectionSessionID
    /// 取得workflowが割り当てたpolling世代です。
    let generation: UInt
    /// manifest構造の明示versionです。
    let manifestVersion: Int
    /// polling方針の明示versionです。
    let pollingPolicyVersion: Int
    /// model入力変換契約の明示versionです。
    let modelInputManifestVersion: Int
    /// formula文字列の比較規則を示す明示versionです。
    let formulaCanonicalizationVersion: Int
    /// 取得開始時点のPID定義一覧です。
    let pidDefinitions: [OBDPIDDefinition]
    /// 取得開始時点のPID能力と収集選択一覧です。
    let pidCapabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]
    /// policyが確定した要求順のService/PID一覧です。
    let orderedRequestedPIDs: [OBDPIDRequest]
    /// 初期化時に判定したアダプターのチップ種別とATMA判定結果です。判定結果がない場合は `nil` です。
    let adapterProbeEvidence: AcquisitionAdapterProbeEvidence?

    /// manifest作成へ渡す確定済み入力を保持します。
    ///
    /// 責務: session、世代、version、PID定義、能力、要求順、アダプター判定結果を推測のない作成要求へまとめます。
    /// - Parameters:
    ///   - sessionID: manifestを所有するsession識別子。
    ///   - generation: 取得workflowが割り当てたpolling世代。
    ///   - manifestVersion: manifest構造の明示version。
    ///   - pollingPolicyVersion: polling方針の明示version。
    ///   - modelInputManifestVersion: model入力変換契約の明示version。
    ///   - formulaCanonicalizationVersion: formula比較規則の明示version。
    ///   - pidDefinitions: 取得開始時点のPID定義一覧。
    ///   - pidCapabilities: 取得開始時点のPID能力と収集選択一覧。
    ///   - orderedRequestedPIDs: policyが確定した要求順のService/PID一覧。
    ///   - adapterProbeEvidence: 初期化時に判定したアダプター判定結果。判定結果がない場合は `nil`。
    init(
        sessionID: ConnectionSessionID,
        generation: UInt,
        manifestVersion: Int,
        pollingPolicyVersion: Int,
        modelInputManifestVersion: Int,
        formulaCanonicalizationVersion: Int,
        pidDefinitions: [OBDPIDDefinition],
        pidCapabilities: [ConnectionSessionAcquisitionPIDCapabilityInput],
        orderedRequestedPIDs: [OBDPIDRequest],
        adapterProbeEvidence: AcquisitionAdapterProbeEvidence? = nil
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.manifestVersion = manifestVersion
        self.pollingPolicyVersion = pollingPolicyVersion
        self.modelInputManifestVersion = modelInputManifestVersion
        self.formulaCanonicalizationVersion = formulaCanonicalizationVersion
        self.pidDefinitions = pidDefinitions
        self.pidCapabilities = pidCapabilities
        self.orderedRequestedPIDs = orderedRequestedPIDs
        self.adapterProbeEvidence = adapterProbeEvidence
    }
}
