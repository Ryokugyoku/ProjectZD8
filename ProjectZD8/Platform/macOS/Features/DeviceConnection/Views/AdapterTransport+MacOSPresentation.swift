#if os(macOS)
import SwiftUI

extension AdapterTransport {
    /// 責務: 接続方式を表す SF Symbols 名を返す。
    var macOSSymbol: String {
        switch self {
        case .bluetoothLowEnergy, .bluetoothClassic: "dot.radiowaves.left.and.right"
        case .usbSerial: "cable.connector"
        case .demo: "sparkles"
        }
    }

    /// 接続方式の表示名キー。
    var macOSNameKey: LocalizedStringKey {
        switch self {
        case .bluetoothLowEnergy: "device.transport.bluetoothLowEnergy"
        case .bluetoothClassic: "device.transport.bluetoothClassic"
        case .usbSerial: "device.transport.usbSerial"
        case .demo: "device.transport.demo"
        }
    }
}
#endif
