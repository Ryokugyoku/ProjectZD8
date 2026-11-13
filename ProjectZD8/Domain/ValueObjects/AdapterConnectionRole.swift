/// OBDアダプターへ割り当てる製品上の接続役割です。
enum AdapterConnectionRole: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// 通常のOBD診断通信に必須のプライマリー役割を表します。
    case primary

    /// Raw CAN受信専用の任意セカンダリー役割を表します。
    case secondary

    /// 接続役割を一意に識別する安定識別子です。
    var id: String { rawValue }
}
