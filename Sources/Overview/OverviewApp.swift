import AppKit
import SwiftUI

@main
struct OverviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The dashboard window is owned by AppDelegate. A SwiftUI WindowGroup is not
    // used because SwiftUI restores zero windows when the app quit with its window
    // closed, which left the dashboard (and the model started from it) absent.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = StatusModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.showDashboard = { [weak self] in self?.showWindow() }
        model.start()
        showWindow()
    }

    /// Dock icon click with no visible window: show the dashboard again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func showWindow() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    private func makeWindow() -> NSWindow {
        let content = DashboardView()
            .environmentObject(model)
            .frame(minWidth: 900, minHeight: 600)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView = NSHostingView(rootView: content)
        window.center()
        return window
    }
}
