#if os(iOS)
import Foundation

/// ExternalAccessory入出力をMain RunLoop上で対称に開閉します。
@MainActor
struct IOSExternalAccessoryStreamLifecycle {
    /// 入出力ストリームをMain RunLoopへ登録して開きます。
    ///
    /// 責務: 1組のExternalAccessoryストリームをcommon modeで駆動可能な開通処理へ渡します。
    /// - Parameters:
    ///   - inputStream: アクセサリーから受信する入力ストリーム。
    ///   - outputStream: アクセサリーへ送信する出力ストリーム。
    /// - Side Effects: Main RunLoopへの登録後に両ストリームを開きます。
    func open(inputStream: InputStream, outputStream: OutputStream) {
        inputStream.schedule(in: .main, forMode: .common)
        outputStream.schedule(in: .main, forMode: .common)
        inputStream.open()
        outputStream.open()
    }

    /// 入出力ストリームを閉じてMain RunLoopから解除します。
    ///
    /// 責務: 1組のExternalAccessoryストリームを閉鎖してcommon modeの登録を対称に破棄します。
    /// - Parameters:
    ///   - inputStream: アクセサリーから受信していた入力ストリーム。
    ///   - outputStream: アクセサリーへ送信していた出力ストリーム。
    /// - Side Effects: 両ストリームを閉じてMain RunLoopから解除します。
    func close(inputStream: InputStream, outputStream: OutputStream) {
        inputStream.close()
        outputStream.close()
        inputStream.remove(from: .main, forMode: .common)
        outputStream.remove(from: .main, forMode: .common)
    }
}
#endif
