import AppKit
import Foundation

enum TemperatureFormatter {
    static func converted(_ celsius: Double, to unit: TemperatureUnit) -> Double {
        switch unit {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }

    /// Compact value for the menu bar, e.g. "39°" or "103°F".
    static func compact(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius else { return "--°" }
        let value = Int(converted(celsius, to: unit).rounded())
        switch unit {
        case .celsius: return "\(value)°"
        case .fahrenheit: return "\(value)°F"
        }
    }

    /// Value for menu rows, e.g. "39.4°C".
    static func detailed(_ celsius: Double?, unit: TemperatureUnit, decimals: Int = 1) -> String {
        guard let celsius else { return "--" }
        let value = converted(celsius, to: unit)
        return String(format: "%.\(decimals)f%@", value, unit.symbol)
    }
}

enum TemperatureColor {
    static func color(for celsius: Double) -> NSColor {
        switch celsius {
        case ..<60: return .systemGreen
        case ..<80: return .systemOrange
        default: return .systemRed
        }
    }
}

enum MenuFont {
    static let value = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    static let summary = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    static let status = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
}

extension NSAttributedString {
    static func menuRow(name: String, value: String?, color: NSColor = .labelColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 156)]
        let result = NSMutableAttributedString(
            string: name,
            attributes: [
                .font: MenuFont.value,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
        if let value {
            result.append(NSAttributedString(
                string: "\t\(value)",
                attributes: [
                    .font: MenuFont.value,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
            ))
        }
        return result
    }
}
