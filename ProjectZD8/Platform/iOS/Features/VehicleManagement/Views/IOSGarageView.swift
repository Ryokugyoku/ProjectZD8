#if os(iOS)
import SwiftUI

/// ガレージタブの入口です。モデルの状態を読み、操作を送るだけで何も所有しません。
struct IOSGarageView: View {
    let vehicles: VehicleManagementModel
    let maintenance: MaintenanceModel

    var body: some View {
        IOSGarageScreen(
            vehicles: vehicles.state,
            maintenance: maintenance.state,
            sendVehicle: { vehicles.send($0) },
            sendMaintenance: { maintenance.send($0) }
        )
    }
}
#endif
