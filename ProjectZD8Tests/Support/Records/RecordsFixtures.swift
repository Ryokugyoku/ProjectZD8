import Foundation
@testable import ProjectZD8

/// レコード系機能のテストが使うデータの組み立てです。
enum RecordsFixtures {
    /// 固定の基準日時です。
    static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    /// 責務: テスト用の車両を作ります。
    static func vehicle(
        id: VehicleID = VehicleID(),
        name: String = "Car",
        vin: String = "VIN0000000000001",
        powertrain: VehiclePowertrainKind = .combustion,
        energySources: [VehicleEnergySource] = [.gasolineRegular],
        photoID: PhotoID? = nil
    ) -> Vehicle {
        Vehicle(id: id, vin: vin, name: name, powertrain: powertrain, energySources: energySources, photoID: photoID,
                createdAt: referenceDate, modifiedAt: referenceDate)
    }

    /// 責務: テスト用のセッションを作ります。`endedAt` が `nil` なら記録中です。
    static func session(
        id: SessionID = SessionID(),
        vehicleID: VehicleID,
        startedAt: Date = referenceDate,
        duration: TimeInterval? = 600,
        endReason: SessionEndReason? = .userStopped,
        isDemo: Bool = false,
        odometerStart: Double? = nil,
        odometerEnd: Double? = nil,
        sampleCount: Int = 10,
        respondedCount: Int = 8,
        rawAvailability: RawAvailability = .local,
        archiveDigest: String? = nil
    ) -> DriveSession {
        DriveSession(
            id: id,
            vehicleID: vehicleID,
            startedAt: startedAt,
            endedAt: duration.map { startedAt.addingTimeInterval($0) },
            endReason: duration == nil ? nil : endReason,
            isDemo: isDemo,
            adapterName: "Adapter",
            adapterTransport: .bluetoothLowEnergy,
            platform: .mac,
            deviceID: "device",
            deviceName: "Mac",
            appVersion: "1.0",
            appBuild: "1",
            pollingPolicyVersion: 1,
            odometerStartKilometers: odometerStart,
            odometerEndKilometers: odometerEnd,
            distanceSource: odometerEnd == nil ? nil : .odometer,
            sampleCount: sampleCount,
            respondedCount: respondedCount,
            payloadByteCount: 2048,
            rawAvailability: rawAvailability,
            archiveDigest: archiveDigest,
            modifiedAt: startedAt
        )
    }

    /// 責務: テスト用の整備記録を作ります。
    static func maintenance(
        id: MaintenanceRecordID = MaintenanceRecordID(),
        vehicleID: VehicleID,
        kind: MaintenanceKind = .light,
        title: String = "Oil change",
        performedAt: Date = referenceDate,
        photos: [MaintenancePhoto] = []
    ) -> MaintenanceRecord {
        MaintenanceRecord(
            id: id, vehicleID: vehicleID, kind: kind, title: title, performedAt: performedAt,
            workItems: [MaintenanceWorkItem(component: .engineOil, operation: .replacement)],
            photos: photos, createdAt: referenceDate, modifiedAt: referenceDate
        )
    }
}

/// 条件が満たされるまで、メインアクターを譲りながら待ちます。
///
/// 責務: 変更通知による非同期の再読み込みをテストが待てるようにします。
/// - Returns: 制限時間内に条件が満たされたかどうか。
@MainActor
func recordsEventually(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
