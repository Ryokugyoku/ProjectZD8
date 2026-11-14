import Foundation

/// CANバスから受信した1件の未デコードフレームです。
nonisolated struct CANFrameObservation: Equatable, Sendable {
    /// 呼び出し側が採番したセッション内の記録順序です。
    let sequence: Int64
    /// フレームを受信した連続取得区間の番号です。
    let segmentOrdinal: Int
    /// フレームを受信した実時間です。永続化ではmicrosecond精度へ丸めます。
    let receivedAt: Date
    /// フレーム受信時に採取した単調時計のナノ秒値です。
    let monotonicNanoseconds: UInt64
    /// 11bitまたは29bitのCAN識別子です。
    let canIdentifier: UInt32
    /// 未デコードのデータバイトです。CAN FDの上限である64バイト以下で保存できます。
    let payload: [UInt8]

    /// 受信CANフレームを生成します。
    ///
    /// 責務: 1件の未デコードCANフレームを採番済みの記録順序と所属区間へ固定します。
    /// - Parameters:
    ///   - sequence: 呼び出し側が採番したセッション内の記録順序。
    ///   - segmentOrdinal: フレームを受信した連続取得区間の番号。
    ///   - receivedAt: フレームを受信した実時間。
    ///   - monotonicNanoseconds: フレーム受信時に採取した単調時計のナノ秒値。
    ///   - canIdentifier: 11bitまたは29bitのCAN識別子。
    ///   - payload: 未デコードのデータバイト。
    init(
        sequence: Int64,
        segmentOrdinal: Int,
        receivedAt: Date,
        monotonicNanoseconds: UInt64,
        canIdentifier: UInt32,
        payload: [UInt8]
    ) {
        self.sequence = sequence
        self.segmentOrdinal = segmentOrdinal
        self.receivedAt = receivedAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.canIdentifier = canIdentifier
        self.payload = payload
    }
}
