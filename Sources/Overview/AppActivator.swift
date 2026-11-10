import AppKit

/// Brings a source app to the front, launching it if it is not running.
enum AppActivator {
    static let outlookIDs = ["com.microsoft.Outlook"]

    static func activate(bundleIDs: [String]) {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                activate(appURL: url)
                return
            }
        }
    }

    static func activate(appPath: String) {
        guard !appPath.isEmpty else { return }
        activate(appURL: URL(fileURLWithPath: appPath))
    }

    private static func activate(appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
