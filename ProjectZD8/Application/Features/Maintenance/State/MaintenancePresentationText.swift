/// 整備区分を固定ローカライズキーへ写像します。
extension MaintenanceKind {
    /// 画面表示に使用する固定String Catalogキーです。
    var localizationKey: String {
        switch self {
        case .light: "maintenance.kind.light"
        case .heavy: "maintenance.kind.heavy"
        }
    }
}

/// 整備部品を固定ローカライズキーへ写像します。
extension MaintenanceComponent {
    /// 画面表示に使用する固定String Catalogキーです。
    var localizationKey: String {
        switch self {
        case .engineOil: "maintenance.component.engine_oil"
        case .oilFilter: "maintenance.component.oil_filter"
        case .airFilter: "maintenance.component.air_filter"
        case .tires: "maintenance.component.tires"
        case .brakePads: "maintenance.component.brake_pads"
        case .auxiliaryBattery: "maintenance.component.auxiliary_battery"
        case .wipers: "maintenance.component.wipers"
        case .coolant: "maintenance.component.coolant"
        case .transmissionFluid: "maintenance.component.transmission_fluid"
        case .differentialFluid: "maintenance.component.differential_fluid"
        case .sparkPlugs: "maintenance.component.spark_plugs"
        case .belts: "maintenance.component.belts"
        case .bulbs: "maintenance.component.bulbs"
        case .engineAssembly: "maintenance.component.engine_assembly"
        case .transmission: "maintenance.component.transmission"
        case .driveline: "maintenance.component.driveline"
        case .suspension: "maintenance.component.suspension"
        case .steering: "maintenance.component.steering"
        case .brakingSystem: "maintenance.component.braking_system"
        case .exhaust: "maintenance.component.exhaust"
        case .fuelSystem: "maintenance.component.fuel_system"
        case .coolingSystem: "maintenance.component.cooling_system"
        case .electrical: "maintenance.component.electrical"
        case .airConditioning: "maintenance.component.air_conditioning"
        case .safetySystem: "maintenance.component.safety_system"
        case .highVoltageBattery: "maintenance.component.high_voltage_battery"
        case .tractionMotor: "maintenance.component.traction_motor"
        case .bodyFrame: "maintenance.component.body_frame"
        case .other: "maintenance.component.other"
        }
    }
}

/// 整備作業種別を固定ローカライズキーへ写像します。
extension MaintenanceOperation {
    /// 画面表示に使用する固定String Catalogキーです。
    var localizationKey: String {
        switch self {
        case .inspection: "maintenance.operation.inspection"
        case .replacement: "maintenance.operation.replacement"
        case .repair: "maintenance.operation.repair"
        case .adjustment: "maintenance.operation.adjustment"
        case .overhaul: "maintenance.operation.overhaul"
        case .cleaning: "maintenance.operation.cleaning"
        case .diagnosis: "maintenance.operation.diagnosis"
        case .fabrication: "maintenance.operation.fabrication"
        }
    }
}
