import Foundation

/// Starts TempBar at login with a per-user LaunchAgent.
///
/// The agent is written to `~/Library/LaunchAgents` and loaded by launchd at the
/// next login. It is deliberately not bootstrapped right away: doing so would
/// launch a second copy of TempBar while this copy is already running. Removing
/// the agent stops future logins without terminating the current copy.
enum LoginItem {
    enum LoginItemError: LocalizedError {
        case notAnAppBundle

        var errorDescription: String? {
            switch self {
            case .notAnAppBundle:
                return "TempBar must be running from an app bundle to start at login."
            }
        }
    }

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.inar.tempbar"
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleID).plist")
    }

    /// True when an agent exists and points at the copy of TempBar that is
    /// running now. If the app was moved after enabling, this returns false so
    /// toggling the menu item on again repairs the path.
    static var isEnabled: Bool {
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let executable = Bundle.main.executableURL?.path
        else {
            return false
        }
        return arguments.first == executable
    }

    static var needsApproval: Bool { false }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }

    // MARK: - LaunchAgent

    private static func installLaunchAgent() throws {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { throw LoginItemError.notAnAppBundle }

        let executable = Bundle.main.executableURL
            ?? bundleURL.appendingPathComponent("Contents/MacOS/TempBar")

        let plist: [String: Any] = [
            "Label": bundleID,
            "ProgramArguments": [executable.path],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private static func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: launchAgentURL)
    }
}
