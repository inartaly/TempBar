import Foundation

enum MenuBarMode: String, CaseIterable {
    case hottest
    case average
    case both

    var title: String {
        switch self {
        case .hottest: return "Hottest sensor"
        case .average: return "Average of sensors"
        case .both: return "Hottest + average"
        }
    }
}

enum TemperatureUnit: String, CaseIterable {
    case celsius
    case fahrenheit

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let showCPU = "tempbar.showCPU"
        static let showGPU = "tempbar.showGPU"
        static let showLabels = "tempbar.showLabels"
        static let mode = "tempbar.menuBarMode"
        static let colorize = "tempbar.colorize"
        static let unit = "tempbar.unit"
        static let refreshInterval = "tempbar.refreshInterval"
    }

    private let defaults: UserDefaults

    var showCPU: Bool {
        didSet { defaults.set(showCPU, forKey: Key.showCPU) }
    }

    var showGPU: Bool {
        didSet { defaults.set(showGPU, forKey: Key.showGPU) }
    }

    var showLabels: Bool {
        didSet { defaults.set(showLabels, forKey: Key.showLabels) }
    }

    var menuBarMode: MenuBarMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Key.mode) }
    }

    var colorize: Bool {
        didSet { defaults.set(colorize, forKey: Key.colorize) }
    }

    var unit: TemperatureUnit {
        didSet { defaults.set(unit.rawValue, forKey: Key.unit) }
    }

    var refreshInterval: TimeInterval {
        didSet {
            let clamped = min(max(refreshInterval, 1), 60)
            if clamped != refreshInterval {
                refreshInterval = clamped
                return
            }
            defaults.set(refreshInterval, forKey: Key.refreshInterval)
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Key.showCPU: true,
            Key.showGPU: true,
            Key.showLabels: true,
            Key.mode: MenuBarMode.hottest.rawValue,
            Key.colorize: true,
            Key.unit: TemperatureUnit.celsius.rawValue,
            Key.refreshInterval: 2.0
        ])

        showCPU = defaults.bool(forKey: Key.showCPU)
        showGPU = defaults.bool(forKey: Key.showGPU)
        showLabels = defaults.bool(forKey: Key.showLabels)
        menuBarMode = MenuBarMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .hottest
        colorize = defaults.bool(forKey: Key.colorize)
        unit = TemperatureUnit(rawValue: defaults.string(forKey: Key.unit) ?? "") ?? .celsius
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
    }
}
