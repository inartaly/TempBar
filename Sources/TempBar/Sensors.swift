import CSensors
import Foundation

// MARK: - Sensor model

enum SensorGroup: String, CaseIterable {
    case cpu
    case gpu

    var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        }
    }
}

struct SensorReading: Identifiable, Equatable {
    let name: String
    let celsius: Double
    let group: SensorGroup

    var id: String { name }
}

struct GroupReading {
    let group: SensorGroup
    let sensors: [SensorReading]

    static func empty(_ group: SensorGroup) -> GroupReading {
        GroupReading(group: group, sensors: [])
    }

    var count: Int { sensors.count }

    var hottest: Double? {
        sensors.map(\.celsius).max()
    }

    var average: Double? {
        guard !sensors.isEmpty else { return nil }
        return sensors.reduce(0) { $0 + $1.celsius } / Double(sensors.count)
    }
}

struct TemperatureSnapshot {
    let timestamp: Date
    let cpu: GroupReading
    let gpu: GroupReading

    static let empty = TemperatureSnapshot(
        timestamp: .distantPast,
        cpu: .empty(.cpu),
        gpu: .empty(.gpu)
    )

    var hasData: Bool {
        !cpu.sensors.isEmpty || !gpu.sensors.isEmpty
    }

    func group(_ group: SensorGroup) -> GroupReading {
        group == .cpu ? cpu : gpu
    }

    static func make(from readings: [SensorReading]) -> TemperatureSnapshot {
        let cpu = readings.filter { $0.group == .cpu }
        let gpu = readings.filter { $0.group == .gpu }
        return TemperatureSnapshot(
            timestamp: Date(),
            cpu: GroupReading(group: .cpu, sensors: cpu),
            gpu: GroupReading(group: .gpu, sensors: gpu)
        )
    }
}

// MARK: - Reader

/// Reads Apple Silicon CPU/GPU die sensors once per call.
///
/// The private IOKit work lives in the CSensors target. On this platform CPU
/// temperatures are the `PMU tdie*` HID sensors and GPU temperatures are the
/// `PMU tdev*` sensors; no root access or extra permissions are involved.
final class TemperatureReader {
    private let lock = NSLock()

    /// Kept for wake-from-sleep handling. Readings use a fresh HID client each
    /// time, so there is no cached state to invalidate.
    func rebuild() {}

    func readAll() -> [SensorReading] {
        lock.lock()
        defer { lock.unlock() }

        var count: Int32 = 0
        guard let sensors = tbt_read_sensors(&count), count > 0 else {
            return []
        }
        defer { tbt_free_sensors(sensors, count) }

        var readings: [SensorReading] = []
        readings.reserveCapacity(Int(count))

        for index in 0..<Int(count) {
            let sensor = sensors[index]
            guard let namePointer = sensor.name else { continue }

            let group: SensorGroup
            switch sensor.group {
            case 0: group = .cpu
            case 1: group = .gpu
            default: continue
            }

            readings.append(SensorReading(
                name: String(cString: namePointer),
                celsius: sensor.celsius,
                group: group
            ))
        }

        readings.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return readings
    }
}
