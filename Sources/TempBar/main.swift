import AppKit
import Foundation

// A small command-line escape hatch, useful for verifying sensors and scripting:
//   TempBar --dump
//   TempBar --dump --json
if CommandLine.arguments.contains("--dump") {
    let reader = TemperatureReader()
    let readings = reader.readAll()
    let snapshot = TemperatureSnapshot.make(from: readings)

    if CommandLine.arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        struct JSONSensor: Encodable {
            let name: String
            let celsius: Double
        }
        struct JSONGroup: Encodable {
            let hottest: Double?
            let average: Double?
            let sensors: [JSONSensor]
        }
        struct JSONSnapshot: Encodable {
            let cpu: JSONGroup
            let gpu: JSONGroup
            let timestamp: Date
        }

        func encode(_ group: GroupReading) -> JSONGroup {
            JSONGroup(
                hottest: group.hottest,
                average: group.average,
                sensors: group.sensors.map { JSONSensor(name: $0.name, celsius: $0.celsius) }
            )
        }

        let payload = JSONSnapshot(
            cpu: encode(snapshot.cpu),
            gpu: encode(snapshot.gpu),
            timestamp: snapshot.timestamp
        )
        if let data = try? encoder.encode(payload),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        exit(snapshot.hasData ? 0 : 1)
    }

    for group in SensorGroup.allCases {
        let reading = snapshot.group(group)
        print("\(group.displayName) (\(reading.count) sensors)")
        for sensor in reading.sensors {
            print(String(format: "  %-20@ %6.2f°C", sensor.name as NSString, sensor.celsius))
        }
        print(String(
            format: "  hottest %.2f°C   average %.2f°C",
            reading.hottest ?? .nan,
            reading.average ?? .nan
        ))
        print("")
    }

    exit(snapshot.hasData ? 0 : 1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
