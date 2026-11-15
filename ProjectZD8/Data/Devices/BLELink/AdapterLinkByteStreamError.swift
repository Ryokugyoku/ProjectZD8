/// 常駐リンク上のバイトストリーム操作が完了しなかった理由を表します。
nonisolated enum AdapterLinkByteStreamError: Error, Equatable, Sendable {
    /// リンクが `ready` ではないため操作を受け付けませんでした。
    case notReady

    /// 他の利用者が占有し続けたため、待機上限までに占有権を得られませんでした。
    case leaseUnavailable

    /// 渡された占有権が現在の占有者のものではありません(解放済みを含む)。
    case leaseNotHeld

    /// 同じ占有者の読取が進行中のため、新しい読取を受け付けませんでした。
    case readInProgress

    /// 待機上限までにプロンプト `>` が届きませんでした。
    case responseTimedOut

    /// 読取の完了前にリンクが `ready` から外れました。
    case linkLost

    /// 受信バイトがバッファー上限を超えたため、応答境界を保てなくなりました。
    case receiveBufferOverflow

    /// リンクへの書き込みが失敗しました。元の理由を保持します。
    case writeFailed(AdapterLinkWriteError)
}
