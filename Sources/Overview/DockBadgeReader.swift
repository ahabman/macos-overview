import AppKit
import ApplicationServices

/// Reads app badge labels (unread counts) from Dock items through the Accessibility API.
/// Only the badge label is read; no message content.
enum DockBadgeReader {
    enum Badge: Equatable {
        case notRunning
        case none
        case label(String)
    }

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Returns the badge for the first running app among `bundleIDs`.
    static func badge(bundleIDs: [String], dockLabels: [String: String]) -> Badge {
        for id in bundleIDs {
            if let label = dockLabels[id] { return label.isEmpty ? .none : .label(label) }
        }
        let running = bundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        return running ? .none : .notRunning
    }

    /// Map of bundle identifier -> AXStatusLabel ("" when the item has no badge).
    static func readDockLabels() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return [:]
        }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        var result: [String: String] = [:]
        for list in children(of: dockElement) where role(of: list) == kAXListRole as String {
            for item in children(of: list) {
                guard let url = attribute(item, "AXURL") as? URL,
                      let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
                result[bundleID] = attribute(item, "AXStatusLabel") as? String ?? ""
            }
        }
        return result
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute as String) as? String
    }
}
