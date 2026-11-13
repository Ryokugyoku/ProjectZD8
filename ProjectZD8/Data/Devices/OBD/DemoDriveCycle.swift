import Foundation

/// 冷間始動の暖機とアイドル・加速・巡航・減速の繰り返しを時刻の関数として与える、決定的なデモ走行モデルです。
nonisolated struct DemoDriveCycle: Sendable {
    /// 周期内の1キーフレーム(時刻・車速・スロットル・負荷)です。区間は線形補間します。
    private struct Keyframe {
        let time: Double
        let speed: Double
        let throttle: Double
        let load: Double
    }

    /// 1周期(120秒)のキーフレームです。
    private static let cycle: [Keyframe] = [
        Keyframe(time: 0, speed: 0, throttle: 12, load: 22),
        Keyframe(time: 14, speed: 0, throttle: 12, load: 22),
        Keyframe(time: 16, speed: 3, throttle: 38, load: 70),
        Keyframe(time: 34, speed: 80, throttle: 42, load: 78),
        Keyframe(time: 38, speed: 80, throttle: 22, load: 36),
        Keyframe(time: 72, speed: 80, throttle: 21, load: 34),
        Keyframe(time: 76, speed: 78, throttle: 12, load: 12),
        Keyframe(time: 94, speed: 0, throttle: 12, load: 10),
        Keyframe(time: 100, speed: 0, throttle: 12, load: 22),
        Keyframe(time: 120, speed: 0, throttle: 12, load: 22)
    ]

    /// 1周期の長さ [s] です。
    static let cycleDuration: Double = 120
    /// 各ギヤの回転数/車速比 [rpm per km/h] です。
    private static let gearRatios: [Double] = [95, 58, 40, 30, 24]
    /// 1速→2速…の変速車速 [km/h] です。
    private static let shiftSpeeds: [Double] = [22, 38, 56, 72]
    /// 始動時の走行距離計 [km] です。
    private let startingOdometer: Double

    /// 走行モデルを生成します。
    ///
    /// 責務: 始動時の走行距離計を固定した走行モデルを構築します。
    /// - Parameter startingOdometer: 始動時の走行距離計 [km]。
    init(startingOdometer: Double = 48_213.4) {
        self.startingOdometer = startingOdometer
    }

    /// 責務: 始動からの経過時間に対する車両状態を返します。同じ時刻には常に同じ値を返します。
    /// - Parameter elapsed: 始動からの経過時間 [s]。負の値は0として扱います。
    func state(at elapsed: Double) -> DemoVehicleState {
        let t = max(0, elapsed)
        let local = t.truncatingRemainder(dividingBy: Self.cycleDuration)
        let point = interpolated(at: local)
        let coolant = 88 - 68 * exp(-t / 300)
        let warmFraction = min(1, max(0, (coolant - 20) / 68))
        let idleSpeed = 750 + 450 * (1 - warmFraction)
        let engineSpeed = point.speed <= 0.5 ? idleSpeed : max(idleSpeed, point.speed * gearRatio(for: point.speed))
        let load = min(100, point.load + 8 * (1 - warmFraction))
        let distanceKm = distanceMeters(at: t) / 1000
        let intake = 22 + (coolant - 22) * 0.2 - point.speed * 0.02
        let closedLoop = coolant >= 40
        return DemoVehicleState(
            engineSpeed: engineSpeed,
            vehicleSpeed: point.speed,
            engineLoad: load,
            throttle: point.throttle,
            coolantTemperature: coolant,
            intakeTemperature: intake,
            ambientTemperature: 22,
            oilTemperature: 22 + 73 * (1 - exp(-t / 600)),
            transmissionFluidTemperature: 20 + 65 * (1 - exp(-t / 700)),
            manifoldPressure: min(101, 30 + load * 0.7),
            massAirFlow: engineSpeed * 0.02 * load / 100,
            timingAdvance: min(45, max(0, 10 + engineSpeed / 1000 * 3 - load * 0.1)),
            shortTermFuelTrim: closedLoop ? 3 * sin(2 * .pi * t / 6.5) : 0,
            longTermFuelTrim: 1.6,
            fuelLevel: 90 - (distanceKm * 0.08).truncatingRemainder(dividingBy: 80),
            moduleVoltage: 14.0 + 0.2 * sin(t / 5),
            runTime: t.rounded(.down),
            odometer: startingOdometer + distanceKm
        )
    }

    /// 責務: 周期内の時刻でキーフレームを線形補間します。
    private func interpolated(at local: Double) -> (speed: Double, throttle: Double, load: Double) {
        let frames = Self.cycle
        for index in 1..<frames.count where local <= frames[index].time {
            let a = frames[index - 1]
            let b = frames[index]
            let ratio = (local - a.time) / (b.time - a.time)
            return (
                a.speed + (b.speed - a.speed) * ratio,
                a.throttle + (b.throttle - a.throttle) * ratio,
                a.load + (b.load - a.load) * ratio
            )
        }
        let last = frames[frames.count - 1]
        return (last.speed, last.throttle, last.load)
    }

    /// 責務: 車速に対応するギヤの回転数/車速比を返します。
    private func gearRatio(for speed: Double) -> Double {
        let gear = Self.shiftSpeeds.filter { speed >= $0 }.count
        return Self.gearRatios[gear]
    }

    /// 責務: 始動からの走行距離 [m] を、車速の線形区間の台形積分で求めます。
    private func distanceMeters(at t: Double) -> Double {
        let cycles = (t / Self.cycleDuration).rounded(.down)
        let local = t - cycles * Self.cycleDuration
        return cycles * cycleDistanceMeters + distanceMeters(inCycleUpTo: local)
    }

    /// 責務: 1周期で進む距離 [m] です。
    private var cycleDistanceMeters: Double {
        distanceMeters(inCycleUpTo: Self.cycleDuration)
    }

    /// 責務: 周期の先頭から `local` 秒までに進む距離 [m] を返します。
    private func distanceMeters(inCycleUpTo local: Double) -> Double {
        var total = 0.0
        let frames = Self.cycle
        for index in 1..<frames.count {
            let a = frames[index - 1]
            let b = frames[index]
            guard local > a.time else { break }
            let end = min(local, b.time)
            let speedAtEnd = a.speed + (b.speed - a.speed) * (end - a.time) / (b.time - a.time)
            total += (a.speed + speedAtEnd) / 2 / 3.6 * (end - a.time)
        }
        return total
    }
}
