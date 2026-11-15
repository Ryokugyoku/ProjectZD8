import SwiftUI

/// 車両名欄の文言です。登録済みならその名称を、未登録なら既定の文言を描きます。
struct RecordingSessionLiveActivityVehicleNameText: View {
    /// 車両名欄の内容です。
    let vehicle: RecordingSessionActivityAttributes.VehicleLabel

    /// 名称はそのまま、未登録は `unregisteredVehicleKey` をローカライズして描きます。
    var body: some View {
        switch vehicle {
        case .named(let name):
            Text(verbatim: name)
        case .unregistered:
            Text(LocalizedStringKey(RecordingSessionActivityAttributes.unregisteredVehicleKey))
        }
    }
}
