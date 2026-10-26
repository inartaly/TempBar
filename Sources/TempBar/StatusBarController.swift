import AppKit
import Foundation

final class StatusBarController: NSObject, NSMenuDelegate {
    private let prefs = Preferences.shared
    private let reader = TemperatureReader()
    private let samplingQueue = DispatchQueue(label: "com.inar.tempbar.sampling", qos: .utility)

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private var snapshot = TemperatureSnapshot.empty
    private var peakCPU: Double?
    private var peakGPU: Double?
    private var isSampling = false
    private var menuIsOpen = false
    private var needsMenuRebuild = false
    private var sensorSignature = ""

    private var cpuSummaryItem: NSMenuItem!
    private var gpuSummaryItem: NSMenuItem!
    private var peakItem: NSMenuItem!
    private var sensorItems: [String: NSMenuItem] = [:]

    private var showCPUMenuItem: NSMenuItem!
    private var showGPUMenuItem: NSMenuItem!
    private var showLabelsMenuItem: NSMenuItem!
    private var colorizeMenuItem: NSMenuItem!
    private var fahrenheitMenuItem: NSMenuItem!
    private var modeMenuItems: [MenuBarMode: NSMenuItem] = [:]
    private var refreshMenuItems: [TimeInterval: NSMenuItem] = [:]
    private var loginMenuItem: NSMenuItem!

    // MARK: - Lifecycle

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .noImage
            button.title = "TempBar"
            button.toolTip = "TempBar — reading sensors…"
        }

        menu = NSMenu(title: "TempBar")
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 330
        statusItem.menu = menu

        buildMenu()
        updateMenuStates()
        updateStatusTitle()
        restartTimer()
        observeWake()
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    deinit {
        stop()
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reader.rebuild()
            self?.sample()
        }
    }

    // MARK: - Sampling

    private func restartTimer() {
        timer?.invalidate()
        let interval = prefs.refreshInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer.tolerance = min(0.5, interval * 0.2)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        guard !isSampling else { return }
        isSampling = true

        samplingQueue.async { [weak self] in
            guard let self else { return }
            let readings = self.reader.readAll()
            let snapshot = TemperatureSnapshot.make(from: readings)

            DispatchQueue.main.async {
                self.isSampling = false
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ newSnapshot: TemperatureSnapshot) {
        snapshot = newSnapshot

        if let hottest = newSnapshot.cpu.hottest {
            peakCPU = max(peakCPU ?? hottest, hottest)
        }
        if let hottest = newSnapshot.gpu.hottest {
            peakGPU = max(peakGPU ?? hottest, hottest)
        }

        let signature = (newSnapshot.cpu.sensors.map(\.name) + newSnapshot.gpu.sensors.map(\.name))
            .joined(separator: "|")
        if signature != sensorSignature {
            sensorSignature = signature
            needsMenuRebuild = true
            if !menuIsOpen {
                rebuildMenuIfNeeded()
            }
        }

        updateStatusTitle()
        updateDynamicItems()
    }

    // MARK: - Menu construction

    private func buildMenu() {
        menu.removeAllItems()
        sensorItems.removeAll()
        modeMenuItems.removeAll()
        refreshMenuItems.removeAll()

        cpuSummaryItem = disabledItem()
        gpuSummaryItem = disabledItem()
        peakItem = disabledItem()
        menu.addItem(cpuSummaryItem)
        menu.addItem(gpuSummaryItem)
        menu.addItem(peakItem)
        menu.addItem(.separator())

        let sensorsItem = NSMenuItem(title: "Sensors", action: nil, keyEquivalent: "")
        sensorsItem.submenu = makeSensorsMenu()
        menu.addItem(sensorsItem)

        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.submenu = makeDisplayMenu()
        menu.addItem(displayItem)

        let refreshItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        refreshItem.submenu = makeRefreshMenu()
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        loginMenuItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        let aboutItem = NSMenuItem(
            title: "About TempBar",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit TempBar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        cpuSummaryItem.isEnabled = false
        gpuSummaryItem.isEnabled = false
        peakItem.isEnabled = false

        updateDynamicItems()
        needsMenuRebuild = false
    }

    private func makeSensorsMenu() -> NSMenu {
        let submenu = NSMenu(title: "Sensors")
        submenu.autoenablesItems = false

        if snapshot.cpu.sensors.isEmpty && snapshot.gpu.sensors.isEmpty {
            let empty = NSMenuItem(title: "No CPU/GPU temperature sensors found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)

            let help = NSMenuItem(
                title: "TempBar reads Apple Silicon HID sensors. Some Macs do not expose a GPU sensor.",
                action: nil,
                keyEquivalent: ""
            )
            help.isEnabled = false
            submenu.addItem(help)
            return submenu
        }

        for group in SensorGroup.allCases {
            let reading = snapshot.group(group)
            guard !reading.sensors.isEmpty else { continue }

            if submenu.items.count > 0 {
                submenu.addItem(.separator())
            }

            let header = disabledItem()
            header.attributedTitle = NSAttributedString(
                string: "\(group.displayName)  ·  \(reading.count) sensors",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            submenu.addItem(header)

            for sensor in reading.sensors {
                let item = disabledItem()
                item.attributedTitle = sensorTitle(for: sensor)
                submenu.addItem(item)
                sensorItems[sensor.name] = item
            }
        }

        return submenu
    }

    private func makeDisplayMenu() -> NSMenu {
        let submenu = NSMenu(title: "Display")
        submenu.autoenablesItems = false

        showCPUMenuItem = checkableItem("Show CPU temperature", action: #selector(toggleShowCPU))
        showGPUMenuItem = checkableItem("Show GPU temperature", action: #selector(toggleShowGPU))
        showLabelsMenuItem = checkableItem("Show CPU/GPU labels", action: #selector(toggleLabels))
        colorizeMenuItem = checkableItem("Color values by temperature", action: #selector(toggleColorize))
        fahrenheitMenuItem = checkableItem("Use Fahrenheit", action: #selector(toggleFahrenheit))

        submenu.addItem(showCPUMenuItem)
        submenu.addItem(showGPUMenuItem)
        submenu.addItem(showLabelsMenuItem)
        submenu.addItem(.separator())
        submenu.addItem(colorizeMenuItem)
        submenu.addItem(fahrenheitMenuItem)
        submenu.addItem(.separator())

        let modeItem = NSMenuItem(title: "Menu Bar Value", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu(title: "Menu Bar Value")
        modeSubmenu.autoenablesItems = false
        for (index, mode) in MenuBarMode.allCases.enumerated() {
            let item = checkableItem(mode.title, action: #selector(chooseMode(_:)))
            item.tag = index
            modeSubmenu.addItem(item)
            modeMenuItems[mode] = item
        }
        modeItem.submenu = modeSubmenu
        submenu.addItem(modeItem)

        submenu.addItem(.separator())
        let resetItem = NSMenuItem(title: "Reset Session Peak", action: #selector(resetPeak), keyEquivalent: "")
        resetItem.target = self
        submenu.addItem(resetItem)

        return submenu
    }

    private func makeRefreshMenu() -> NSMenu {
        let submenu = NSMenu(title: "Refresh Rate")
        submenu.autoenablesItems = false

        for seconds in [1.0, 2.0, 5.0, 10.0] {
            let item = checkableItem("\(Int(seconds)) second\(seconds == 1 ? "" : "s")", action: #selector(chooseRefresh(_:)))
            item.representedObject = NSNumber(value: seconds)
            submenu.addItem(item)
            refreshMenuItems[seconds] = item
        }

        return submenu
    }

    private func disabledItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func checkableItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func sensorTitle(for sensor: SensorReading) -> NSAttributedString {
        let color = prefs.colorize
            ? TemperatureColor.color(for: sensor.celsius)
            : NSColor.labelColor
        return .menuRow(
            name: sensor.name,
            value: TemperatureFormatter.detailed(sensor.celsius, unit: prefs.unit),
            color: color
        )
    }

    // MARK: - Menu updates

    private func rebuildMenuIfNeeded() {
        guard needsMenuRebuild, !menuIsOpen else { return }
        buildMenu()
        updateMenuStates()
    }

    private func updateDynamicItems() {
        guard menu != nil else { return }

        cpuSummaryItem.attributedTitle = summaryTitle(for: .cpu)
        gpuSummaryItem.attributedTitle = summaryTitle(for: .gpu)

        let peakText = "Peak since launch   CPU \(TemperatureFormatter.detailed(peakCPU, unit: prefs.unit))   GPU \(TemperatureFormatter.detailed(peakGPU, unit: prefs.unit))"
        peakItem.attributedTitle = NSAttributedString(
            string: peakText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        for group in SensorGroup.allCases {
            for sensor in snapshot.group(group).sensors {
                sensorItems[sensor.name]?.attributedTitle = sensorTitle(for: sensor)
            }
        }
    }

    private func summaryTitle(for group: SensorGroup) -> NSAttributedString {
        let reading = snapshot.group(group)
        let prefix = "\(group.displayName)   "

        let detail: String
        if reading.sensors.isEmpty {
            detail = "--  ·  no sensors"
        } else {
            let hottest = TemperatureFormatter.detailed(reading.hottest, unit: prefs.unit)
            let average = TemperatureFormatter.detailed(reading.average, unit: prefs.unit)
            let noun = reading.count == 1 ? "sensor" : "sensors"
            detail = "\(hottest) hot  ·  \(average) avg  ·  \(reading.count) \(noun)"
        }

        return NSAttributedString(
            string: prefix + detail,
            attributes: [
                .font: MenuFont.summary,
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func updateMenuStates() {
        showCPUMenuItem?.state = prefs.showCPU ? .on : .off
        showGPUMenuItem?.state = prefs.showGPU ? .on : .off
        showLabelsMenuItem?.state = prefs.showLabels ? .on : .off
        colorizeMenuItem?.state = prefs.colorize ? .on : .off
        fahrenheitMenuItem?.state = prefs.unit == .fahrenheit ? .on : .off

        for (mode, item) in modeMenuItems {
            item.state = prefs.menuBarMode == mode ? .on : .off
        }
        for (seconds, item) in refreshMenuItems {
            item.state = abs(prefs.refreshInterval - seconds) < 0.01 ? .on : .off
        }

        loginMenuItem?.state = LoginItem.isEnabled ? .on : .off
    }

    private func preferencesChanged(restartSamplingTimer: Bool = false) {
        updateMenuStates()
        updateStatusTitle()
        updateDynamicItems()
        if restartSamplingTimer {
            restartTimer()
        }
    }

    // MARK: - Status item

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }

        if !snapshot.hasData {
            let placeholder = placeholders()
            button.attributedTitle = NSAttributedString(
                string: placeholder.isEmpty ? "°" : placeholder,
                attributes: [
                    .font: MenuFont.status,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            button.toolTip = "TempBar — no sensor readings yet"
            button.setAccessibilityLabel("TempBar, no sensor readings yet")
            return
        }

        var groups: [(SensorGroup, GroupReading)] = []
        if prefs.showCPU { groups.append((.cpu, snapshot.cpu)) }
        if prefs.showGPU { groups.append((.gpu, snapshot.gpu)) }

        let withData = groups.filter { $0.1.count > 0 }
        if !withData.isEmpty {
            groups = withData
        }

        let title = NSMutableAttributedString()

        func append(_ text: String, color: NSColor) {
            title.append(NSAttributedString(
                string: text,
                attributes: [
                    .font: MenuFont.status,
                    .foregroundColor: color
                ]
            ))
        }

        for (index, entry) in groups.enumerated() {
            let (group, reading) = entry
            if index > 0 {
                append("  ", color: .secondaryLabelColor)
            }
            if prefs.showLabels {
                append("\(group.displayName) ", color: .labelColor)
            }

            let hottest = reading.hottest
            let average = reading.average
            let text: String
            switch prefs.menuBarMode {
            case .hottest:
                text = TemperatureFormatter.compact(hottest, unit: prefs.unit)
            case .average:
                text = TemperatureFormatter.compact(average, unit: prefs.unit)
            case .both:
                text = "\(TemperatureFormatter.compact(hottest, unit: prefs.unit)) (\(TemperatureFormatter.compact(average, unit: prefs.unit)))"
            }

            let color: NSColor
            if prefs.colorize, let hottest {
                color = TemperatureColor.color(for: hottest)
            } else {
                color = .labelColor
            }
            append(text, color: color)
        }

        if title.length == 0 {
            append("°", color: .secondaryLabelColor)
        }

        button.attributedTitle = title
        button.toolTip = tooltipText()
        button.setAccessibilityLabel(accessibilityText())
    }

    private func placeholders() -> String {
        var parts: [String] = []
        if prefs.showCPU { parts.append("CPU --°") }
        if prefs.showGPU { parts.append("GPU --°") }
        return parts.joined(separator: "  ")
    }

    private func tooltipText() -> String {
        var lines = ["TempBar"]
        for group in SensorGroup.allCases {
            let reading = snapshot.group(group)
            guard !reading.sensors.isEmpty else { continue }
            let hottest = TemperatureFormatter.detailed(reading.hottest, unit: prefs.unit)
            let average = TemperatureFormatter.detailed(reading.average, unit: prefs.unit)
            lines.append("\(group.displayName)  \(hottest) hot · \(average) avg (\(reading.count) sensors)")
        }
        if let cpu = peakCPU {
            lines.append("Peak  CPU \(TemperatureFormatter.detailed(cpu, unit: prefs.unit))")
        }
        if let gpu = peakGPU {
            lines.append("Peak  GPU \(TemperatureFormatter.detailed(gpu, unit: prefs.unit))")
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        lines.append("Updated \(formatter.string(from: snapshot.timestamp))")
        return lines.joined(separator: "\n")
    }

    private func accessibilityText() -> String {
        var parts: [String] = []
        for group in SensorGroup.allCases {
            let reading = snapshot.group(group)
            guard !reading.sensors.isEmpty else { continue }
            if let hottest = reading.hottest {
                parts.append("\(group.displayName) \(Int(TemperatureFormatter.converted(hottest, to: prefs.unit).rounded())) degrees")
            }
        }
        return parts.isEmpty ? "TempBar" : parts.joined(separator: ", ")
    }

    // MARK: - Actions

    @objc private func toggleShowCPU() {
        prefs.showCPU.toggle()
        preferencesChanged()
    }

    @objc private func toggleShowGPU() {
        prefs.showGPU.toggle()
        preferencesChanged()
    }

    @objc private func toggleLabels() {
        prefs.showLabels.toggle()
        preferencesChanged()
    }

    @objc private func toggleColorize() {
        prefs.colorize.toggle()
        preferencesChanged()
    }

    @objc private func toggleFahrenheit() {
        prefs.unit = prefs.unit == .celsius ? .fahrenheit : .celsius
        preferencesChanged()
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard MenuBarMode.allCases.indices.contains(sender.tag) else { return }
        prefs.menuBarMode = MenuBarMode.allCases[sender.tag]
        preferencesChanged()
    }

    @objc private func chooseRefresh(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        prefs.refreshInterval = number.doubleValue
        preferencesChanged(restartSamplingTimer: true)
    }

    @objc private func toggleLogin() {
        let enable = !LoginItem.isEnabled
        do {
            try LoginItem.setEnabled(enable)
            if enable, LoginItem.needsApproval {
                showAlert(
                    title: "Approval needed",
                    message: "macOS registered TempBar as a login item but needs your approval. Open System Settings → General → Login Items and enable TempBar."
                )
            }
        } catch {
            showAlert(title: "Couldn’t update login item", message: error.localizedDescription)
        }
        updateMenuStates()
    }

    @objc private func resetPeak() {
        peakCPU = snapshot.cpu.hottest
        peakGPU = snapshot.gpu.hottest
        updateDynamicItems()
    }

    @objc private func showAbout() {
        showAlert(
            title: "TempBar",
            message: """
            A lightweight CPU and GPU temperature monitor for the menu bar.

            CPU temperature is the hottest of the Apple Silicon “PMU tdie” die sensors. GPU temperature is the hottest of the “PMU tdev” sensors. Temperatures are read directly from IOKit HID sensors, so no sudo access, kernel extension, or special permission is required.

            Menu bar values can show the hottest sensor, the average of the sensors, or both. Green is below 60°C, orange is 60–80°C, and red is above 80°C.

            All readings stay on this Mac.
            """
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        updateMenuStates()
        updateDynamicItems()
        sample()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        rebuildMenuIfNeeded()
    }
}
