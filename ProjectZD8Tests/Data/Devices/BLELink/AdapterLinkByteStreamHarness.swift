import Foundation
@testable import ProjectZD8

/// 台本付きリンク fake と、それを受信元にするバイトストリームの組です。
///
/// 待機は実時間を縮めた sleep を注入するため、15秒・10秒などの上限も数十〜数百ミリ秒で終わります。
@MainActor
struct AdapterLinkByteStreamHarness {
    /// 実時間を縮める倍率の既定値です(200分の1)。
    static let defaultTimeScale: Int64 = 200

    /// 受信元のリンク fake です。
    let link: ScriptedAdapterLinkFake
    /// テスト対象のバイトストリームです。
    let stream: AdapterLinkByteStream

    /// リンク fake とバイトストリームを生成します。
    ///
    /// 責務: 指定の上限と時間倍率でバイトストリームをリンク fake へ結び付けます。
    /// - Parameters:
    ///   - state: リンク fake の初期状態。
    ///   - limits: バイトストリームの待機上限と容量。
    ///   - timeScale: 待機時間を割る倍率。
    init(
        state: AdapterLinkState = .ready,
        limits: AdapterLinkByteStreamLimits = .standard,
        timeScale: Int64 = Self.defaultTimeScale
    ) {
        let link = ScriptedAdapterLinkFake(state: state)
        self.link = link
        stream = AdapterLinkByteStream(link: link, limits: limits) { duration in
            try await Task.sleep(for: duration / timeScale)
        }
    }

    /// 切断状態の例です。
    static let disconnected = AdapterLinkState.disconnected(.peripheralDisconnected(errorDescription: nil))
}
