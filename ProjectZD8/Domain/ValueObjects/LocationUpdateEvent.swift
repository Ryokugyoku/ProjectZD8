/// 位置の流れの要素です。
nonisolated enum LocationUpdateEvent: Equatable, Sendable {
    /// 位置が1点得られました。
    case fix(LocationFix)
    /// 位置を取得できない状態になりました。
    case unavailable(LocationUnavailableReason)
}
