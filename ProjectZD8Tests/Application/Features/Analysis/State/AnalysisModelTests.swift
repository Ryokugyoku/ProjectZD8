import XCTest
@testable import ProjectZD8

/// 分析モデルの読み込み・復元・比較・書き出しの流れを検証します。
@MainActor
final class AnalysisModelTests: XCTestCase {
    private typealias F = AnalysisFixtures

    /// テストごとの部品一式です。
    private struct Harness {
        let model: AnalysisModel
        let sessions: AnalysisFakeSessionRepository
        let cloud: AnalysisFakeCloudSync
        let store: AnalysisDatasetStore
        let vehicle: Vehicle
    }

    /// 責務: 検証用のモデルを作ります。
    private func makeHarness(cloudFailure: CloudSyncFailure? = nil) -> Harness {
        let vehicle = F.vehicle()
        let sessions = AnalysisFakeSessionRepository()
        let vehicles = AnalysisFakeVehicleRepository([vehicle])
        let maintenance = AnalysisFakeMaintenanceRepository()
        let names = AnalysisFakeNameResolver()
        let decoder = AnalysisSessionDecoder(sessions: sessions)
        let cloud = AnalysisFakeCloudSync(sessions: sessions, failure: cloudFailure)
        let store = AnalysisDatasetStore()
        let model = AnalysisModel(
            languageCode: "ja",
            sessions: sessions,
            vehicles: vehicles,
            cloudSync: cloud,
            buildDataset: BuildAnalysisDatasetUseCase(decoder: decoder, vehicles: vehicles, maintenance: maintenance, names: names),
            buildTrend: BuildVehicleTrendDatasetUseCase(sessions: sessions, decoder: decoder, vehicles: vehicles, maintenance: maintenance, names: names),
            store: store
        )
        return Harness(model: model, sessions: sessions, cloud: cloud, store: store, vehicle: vehicle)
    }

    /// 責務: 1件だけ応答サンプルを持つセッションを登録して返します。
    @discardableResult
    private func seedSession(_ harness: Harness, offset: Double = 0, raw: RawAvailability = .local) async -> DriveSession {
        let session = F.session(vehicleID: harness.vehicle.id, startedAt: Date(timeIntervalSince1970: 1_000_000 + offset), raw: raw, sampleCount: 1)
        await harness.sessions.seed(
            session,
            pids: [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)],
            samples: raw == .local ? [F.sample(0, seconds: 0, F.speed, payload: [50])] : []
        )
        return session
    }

    /// 責務: 車両の一覧と先頭車両のセッション一覧が読み込まれることを確認します。
    func testAppearedLoadsVehiclesAndSessionOptions() async {
        let harness = makeHarness()
        let session = await seedSession(harness)
        await harness.model.perform(.appeared)
        XCTAssertEqual(harness.model.state.vehicles.map(\.name), ["Test Car"])
        XCTAssertEqual(harness.model.state.selectedVehicleID, harness.vehicle.id)
        XCTAssertEqual(harness.model.state.sessionOptions.map(\.id), [session.id])
        XCTAssertEqual(harness.model.state.phase, .idle)
    }

    /// 責務: 端末内のセッションを開くとデータセットがストアへ置かれることを確認します。
    func testOpenLocalSessionBecomesReady() async throws {
        let harness = makeHarness()
        let session = await seedSession(harness)
        await harness.model.perform(.openSession(session.id))
        let state = harness.model.state
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.loadedSessions.map(\.id), [session.id])
        XCTAssertEqual(state.selectedVehicleID, harness.vehicle.id)
        XCTAssertEqual(state.contentRevision, 1)
        let json = try XCTUnwrap(harness.store.data(forPath: state.loadedSessions[0].datasetPath))
        XCTAssertFalse(json.isEmpty)
        let host = AnalysisHostMessage(state: state)
        XCTAssertEqual(host.sessions.map(\.datasetPath), [state.loadedSessions[0].datasetPath])
        XCTAssertEqual(host.phase, "ready")
    }

    /// 責務: iCloudにだけあるRawは確認を待ち、承諾後にダウンロードして読み込むことを確認します。
    func testCloudOnlyAsksThenDownloads() async {
        let harness = makeHarness()
        let session = await seedSession(harness, raw: .cloudOnly)
        await harness.model.perform(.openSession(session.id))
        XCTAssertEqual(harness.model.state.phase, .awaitingDownloadConsent(session.id))
        let restoredBefore = await harness.cloud.restored
        XCTAssertTrue(restoredBefore.isEmpty, "承諾前にダウンロードしない")

        // 承諾後は復元でローカルへ戻るが、フェイクのRawは空なのでサンプル無しになる。
        await harness.sessions.seed(
            F.session(vehicleID: harness.vehicle.id, startedAt: session.startedAt, raw: .cloudOnly, sampleCount: 1).withID(session.id),
            pids: [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)],
            samples: [F.sample(0, seconds: 0, F.speed, payload: [50])]
        )
        await harness.model.perform(.confirmDownload)
        let restored = await harness.cloud.restored
        XCTAssertEqual(restored, [session.id])
        XCTAssertEqual(harness.model.state.phase, .ready)
        XCTAssertEqual(harness.model.state.loadedSessions.map(\.id), [session.id])
    }

    /// 責務: ダウンロードを断ると何も読み込まないことを確認します。
    func testDeclineDownloadReturnsToIdle() async {
        let harness = makeHarness()
        let session = await seedSession(harness, raw: .cloudOnly)
        await harness.model.perform(.openSession(session.id))
        await harness.model.perform(.declineDownload)
        XCTAssertEqual(harness.model.state.phase, .idle)
        XCTAssertTrue(harness.model.state.loadedSessions.isEmpty)
        let restored = await harness.cloud.restored
        XCTAssertTrue(restored.isEmpty)
    }

    /// 責務: ダウンロード失敗を型付きの失敗として表すことを確認します。
    func testDownloadFailureIsTyped() async {
        let harness = makeHarness(cloudFailure: .network)
        let session = await seedSession(harness, raw: .cloudOnly)
        await harness.model.perform(.openSession(session.id))
        await harness.model.perform(.confirmDownload)
        XCTAssertEqual(harness.model.state.phase, .failed(.downloadFailed(.network)))
        await harness.model.perform(.dismissFailure)
        XCTAssertEqual(harness.model.state.phase, .idle)
    }

    /// 責務: 比較は最大3件で、4件目は失敗し、主セッションは外せないことを確認します。
    func testComparisonLimitAndRemoval() async {
        let harness = makeHarness()
        let first = await seedSession(harness, offset: 0)
        let second = await seedSession(harness, offset: 10)
        let third = await seedSession(harness, offset: 20)
        let fourth = await seedSession(harness, offset: 30)
        await harness.model.perform(.openSession(first.id))
        await harness.model.perform(.addComparisonSession(second.id))
        await harness.model.perform(.addComparisonSession(third.id))
        XCTAssertEqual(harness.model.state.loadedSessions.count, 3)
        await harness.model.perform(.addComparisonSession(fourth.id))
        XCTAssertEqual(harness.model.state.phase, .failed(.tooManySessions))
        XCTAssertEqual(harness.model.state.loadedSessions.count, 3)

        await harness.model.perform(.removeSession(first.id))
        XCTAssertEqual(harness.model.state.loadedSessions.count, 3, "主セッションは外せない")
        await harness.model.perform(.removeSession(third.id))
        XCTAssertEqual(harness.model.state.loadedSessions.map(\.id), [first.id, second.id])
        XCTAssertNil(harness.store.data(forPath: AnalysisDatasetStore.datasetPath(for: third.id)))
    }

    /// 責務: 主セッションを開き直すと、前のセッションのデータを破棄することを確認します。
    func testReplacingPrimaryDropsPreviousDatasets() async {
        let harness = makeHarness()
        let first = await seedSession(harness, offset: 0)
        let second = await seedSession(harness, offset: 10)
        await harness.model.perform(.openSession(first.id))
        await harness.model.perform(.openSession(second.id))
        XCTAssertEqual(harness.model.state.loadedSessions.map(\.id), [second.id])
        XCTAssertNil(harness.store.data(forPath: AnalysisDatasetStore.datasetPath(for: first.id)))
    }

    /// 責務: 存在しないセッションは型付きの失敗になることを確認します。
    func testMissingSessionFails() async {
        let harness = makeHarness()
        await harness.model.perform(.openSession(SessionID()))
        XCTAssertEqual(harness.model.state.phase, .failed(.sessionNotFound))
    }

    /// 責務: 長期傾向を集計するとストアへ置かれ、ホストメッセージにパスが載ることを確認します。
    func testRequestTrend() async throws {
        let harness = makeHarness()
        let session = await seedSession(harness)
        await harness.model.perform(.openSession(session.id))
        await harness.model.perform(.requestTrend(includeDemo: false))
        XCTAssertEqual(harness.model.state.trend, .ready(harness.vehicle.id))
        XCTAssertEqual(harness.model.state.phase, .ready)
        let path = AnalysisDatasetStore.trendPath(for: harness.vehicle.id)
        XCTAssertNotNil(harness.store.data(forPath: path))
        XCTAssertEqual(AnalysisHostMessage(state: harness.model.state).trendPath, path)
    }

    /// 責務: Webからの書き出しを保持し、保存後に解放することを確認します。
    func testExportRoundTrip() async {
        let harness = makeHarness()
        let request = AnalysisExportRequest(filename: "a.csv", mimeType: "text/csv", data: Data("x".utf8))
        await harness.model.perform(.receiveExport(request))
        XCTAssertEqual(harness.model.state.pendingExport, request)
        await harness.model.perform(.finishExport)
        XCTAssertNil(harness.model.state.pendingExport)
    }

    /// 責務: セッション選択UIの要求と、比較数の上限時の拒否を確認します。
    func testPickerRequests() async {
        let harness = makeHarness()
        await harness.model.perform(.requestSessionPicker(.addComparison))
        XCTAssertEqual(harness.model.state.pickerPurpose, .addComparison)
        await harness.model.perform(.dismissSessionPicker)
        XCTAssertNil(harness.model.state.pickerPurpose)
    }
}

private extension DriveSession {
    /// 責務: 同じ内容で識別値だけ差し替えたセッションを返します(テスト専用)。
    func withID(_ id: SessionID) -> DriveSession {
        DriveSession(
            id: id, vehicleID: vehicleID, startedAt: startedAt, endedAt: endedAt, endReason: endReason, isDemo: isDemo,
            adapterName: adapterName, adapterTransport: adapterTransport, platform: platform, deviceID: deviceID, deviceName: deviceName,
            appVersion: appVersion, appBuild: appBuild, pollingPolicyVersion: pollingPolicyVersion,
            odometerStartKilometers: odometerStartKilometers, odometerEndKilometers: odometerEndKilometers, distanceSource: distanceSource,
            sampleCount: sampleCount, respondedCount: respondedCount, rawAvailability: .local, modifiedAt: modifiedAt
        )
    }
}
