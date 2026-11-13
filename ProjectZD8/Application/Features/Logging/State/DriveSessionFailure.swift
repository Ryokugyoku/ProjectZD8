/// 記録の流れで起きた失敗です。失敗した段階を併せて持ちます。
nonisolated struct DriveSessionFailure: Equatable, Sendable {
    /// 失敗の種類です。
    nonisolated enum Kind: Equatable, Sendable {
        /// アダプターまたは車両との通信に失敗した。
        case link(OBDLinkError)
        /// 車両がVINを返さなかったため車両を特定できない。
        case vinMissing
        /// 収集できるPIDが1件も無い。
        case noPollablePIDs
        /// 車両・セッションの保存に失敗した。
        case store
    }

    /// 失敗が起きた段階です。
    let phase: DriveSessionPhase
    let kind: Kind

    /// 責務: 失敗した段階と種類をまとめます。
    init(phase: DriveSessionPhase, kind: Kind) {
        self.phase = phase
        self.kind = kind
    }

    /// 画面表示用のローカライズキーです。
    var localizationKey: String {
        switch kind {
        case .link(let error):
            switch error {
            case .transportUnsupported: "drive.failure.link.transportUnsupported"
            case .connectionFailed: "drive.failure.link.connectionFailed"
            case .adapterRejected: "drive.failure.link.adapterRejected"
            case .connectionLost: "drive.failure.link.connectionLost"
            case .timedOut: "drive.failure.link.timedOut"
            case .vinUnavailable: "drive.failure.vinMissing"
            }
        case .vinMissing: "drive.failure.vinMissing"
        case .noPollablePIDs: "drive.failure.noPollablePIDs"
        case .store: "drive.failure.store"
        }
    }
}
