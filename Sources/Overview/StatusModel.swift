import AppKit
import EventKit
import SwiftUI

@MainActor
final class StatusModel: ObservableObject {
    static let slackIDs = ["com.tinyspeck.slackmacgap"]
    static let teamsIDs = ["com.microsoft.teams2", "com.microsoft.teams"]

    @Published var now = Date()
    @Published var accessibilityTrusted = false
    @Published var slack: DockBadgeReader.Badge = .notRunning
    @Published var teams: DockBadgeReader.Badge = .notRunning
    @Published var calendarAccess: CalendarReader.Access = .unknown
    @Published var meetings: [CalendarReader.Meeting] = []
    @Published var sessions: [ClaudeSessionReader.Session] = []
    @Published var slackUnread: [SlackUnread] = []
    @Published var slackLiveState: SlackLiveClient.State = .notConfigured

    private let slackLive = SlackLiveClient()
    /// Set by AppDelegate: brings the dashboard window to the front in full screen.
    var showDashboard: (() -> Void)?

    private let calendar = CalendarReader()
    private var timer: Timer?
    private var lastCalendarRefresh = Date.distantPast

    func start() {
        accessibilityTrusted = DockBadgeReader.isTrusted(prompt: true)
        slackLive.onChange = { [weak self] in
            guard let self else { return }
            self.slackUnread = self.slackLive.unread.values.sorted { $0.latest > $1.latest }
            self.slackLiveState = self.slackLive.state
        }
        slackLive.start()
        Task {
            await calendar.requestAccess()
            calendarAccess = calendar.access
            refreshCalendar()
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: calendar.store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshCalendar() }
        }
        refreshFast()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        refreshFast()
        if now.timeIntervalSince(lastCalendarRefresh) >= 60 { refreshCalendar() }
        refocusWhenIdle()
    }

    /// Set when Overview was brought forward in the current idle period;
    /// cleared on the next keyboard or mouse input.
    private var refocusedWhileIdle = false

    /// Brings Overview to the front in full screen after no keyboard or mouse
    /// input for `idleMinutes` (default 15; override with
    /// `defaults write com.bamfhealth.overview idleMinutes <n>`).
    private func refocusWhenIdle() {
        let configured = UserDefaults.standard.double(forKey: "idleMinutes")
        let threshold = (configured > 0 ? configured : 15) * 60
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)

        guard idle >= threshold else {
            refocusedWhileIdle = false
            return
        }
        guard !refocusedWhileIdle else { return }
        refocusedWhileIdle = true

        showDashboard?()
        DebugLog.write("refocused after \(Int(idle))s idle")
    }

    private func refreshFast() {
        now = Date()
        accessibilityTrusted = DockBadgeReader.isTrusted(prompt: false)
        let labels = accessibilityTrusted ? DockBadgeReader.readDockLabels() : [:]
        slack = DockBadgeReader.badge(bundleIDs: Self.slackIDs, dockLabels: labels)
        teams = DockBadgeReader.badge(bundleIDs: Self.teamsIDs, dockLabels: labels)
        // Test override: `defaults write com.bamfhealth.overview simulateSlack 3`
        // (or simulateTeams); `defaults delete ...` to stop.
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "simulateSlack"), !value.isEmpty { slack = .label(value) }
        if let value = defaults.string(forKey: "simulateTeams"), !value.isEmpty { teams = .label(value) }
        // Slack's badge clears when everything is read; drop the conversation list with it.
        if slack == .none { slackLive.clearUnread() }
        sessions = ClaudeSessionReader.read(now: now)
        let summary = "sessions=\(sessions.count) titled=\(sessions.filter { $0.title != nil }.count) trusted=\(accessibilityTrusted) dockItems=\(labels.count) slack=\(slack) teams=\(teams) labels=\(labels.filter { !$0.value.isEmpty })"
        if summary != lastLog { DebugLog.write(summary); lastLog = summary }
    }
    private var lastLog = ""

    private func refreshCalendar() {
        lastCalendarRefresh = Date()
        meetings = calendar.nextMeetings(limit: 4)
    }
}
