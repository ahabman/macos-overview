import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: StatusModel

    var body: some View {
        VStack(spacing: 24) {
            header
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    SessionsTile(sessions: model.sessions, now: model.now)
                    MeetingTile(meetings: model.meetings, access: model.calendarAccess, now: model.now)
                        .onTapGesture { AppActivator.activate(bundleIDs: AppActivator.outlookIDs) }
                }
                HStack(spacing: 12) {
                    BadgeTile(title: "Slack", badge: model.slack, trusted: model.accessibilityTrusted,
                              conversations: model.slackUnread, liveState: model.slackLiveState)
                        .onTapGesture { AppActivator.activate(bundleIDs: StatusModel.slackIDs) }
                    BadgeTile(title: "Teams", badge: model.teams, trusted: model.accessibilityTrusted)
                        .onTapGesture { AppActivator.activate(bundleIDs: StatusModel.teamsIDs) }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Spacer()
            Text(model.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(model.now, format: .dateTime.hour().minute())
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

private struct Tile<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 20, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.tile))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}

private struct BadgeTile: View {
    let title: String
    let badge: DockBadgeReader.Badge
    let trusted: Bool
    var conversations: [SlackUnread] = []
    var liveState: SlackLiveClient.State = .notConfigured

    var body: some View {
        Tile(title: title) {
            if !trusted {
                Message("Grant Accessibility access in System Settings > Privacy & Security > Device Control and Data Access.")
            } else {
                switch badge {
                case .notRunning:
                    Message("Not running")
                case .none:
                    BigText("0", color: Theme.green)
                case .label(let text):
                    BigText(text == "•" ? "New" : text, color: Theme.orange)
                    ForEach(conversations.prefix(4)) { conversation in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(conversation.title)
                                .font(.system(size: 26, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(shortTime(conversation.latest))
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            if case .failed(let reason) = liveState {
                Message("Slack live events: \(reason)")
            }
        }
    }
}

private struct MeetingTile: View {
    let meetings: [CalendarReader.Meeting]
    let access: CalendarReader.Access
    let now: Date

    var body: some View {
        Tile(title: "Next meetings") {
            switch access {
            case .unknown:
                Message("Requesting calendar access…")
            case .denied:
                Message("Grant Calendar access in System Settings > Privacy & Security > Calendars.")
            case .granted:
                if let meeting = meetings.first {
                    Text(meeting.title)
                        .font(.system(size: 44, weight: .semibold))
                        .lineLimit(2)
                    Text(when(meeting))
                        .font(.system(size: 32, weight: .medium))
                        .monospacedDigit()
                    if let relative = relative(meeting) {
                        StatusPill(relative, fill: color(meeting), size: 28)
                    }
                    ForEach(Array(meetings.dropFirst().enumerated()), id: \.offset) { _, later in
                        Divider().overlay(Color.white.opacity(0.15))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(later.title)
                                .font(.system(size: 26, weight: .medium))
                                .lineLimit(1)
                            Text(when(later))
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Message("No meetings in the next 7 days")
                }
            }
        }
    }

    /// e.g. "Monday 9:30 - 10:20".
    private func when(_ m: CalendarReader.Meeting) -> String {
        "\(m.start.formatted(.dateTime.weekday(.wide))) \(time(m.start)) - \(time(m.end))"
    }

    private func time(_ date: Date) -> String { shortTime(date) }

    /// Countdown for meetings in progress or later today; nil for other days.
    private func relative(_ m: CalendarReader.Meeting) -> String? {
        if m.start <= now { return "Now" }
        let minutes = Int(m.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "in \(minutes) min" }
        if !Calendar.current.isDate(m.start, inSameDayAs: now) { return nil }
        return "in \(minutes / 60) h \(minutes % 60) min"
    }

    private func color(_ m: CalendarReader.Meeting) -> Color {
        let seconds = m.start.timeIntervalSince(now)
        if seconds <= 0 { return Theme.red }
        if seconds <= 10 * 60 { return Theme.orange }
        return Theme.green
    }
}

private struct SessionsTile: View {
    let sessions: [ClaudeSessionReader.Session]
    let now: Date

    var body: some View {
        Tile(title: "Claude") {
            if sessions.isEmpty {
                Message("No active sessions")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sessions.prefix(8)) { session in
                        HStack(spacing: 14) {
                            Circle().fill(color(session.state)).frame(width: 18, height: 18)
                            Text(session.name)
                                .font(.system(size: 28, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            StatusPill(label(session.state), fill: color(session.state), size: 22)
                            Text(age(session.updated))
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { AppActivator.activate(appPath: session.appPath) }
                    }
                    if sessions.count > 8 {
                        Message("+\(sessions.count - 8) more")
                    }
                }
            }
        }
    }

    private func label(_ state: String) -> String {
        switch state {
        case "waiting": return "Needs input"
        case "working": return "Working"
        case "idle": return "Idle"
        case "error": return "Error"
        default: return state
        }
    }

    private func color(_ state: String) -> Color {
        switch state {
        case "waiting": return Theme.orange
        case "working": return Theme.teal
        case "error": return Theme.red
        default: return Theme.blue
        }
    }

    private func age(_ date: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

private struct BigText: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.system(size: 120, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

private struct Message: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
    }
}

/// White label on a colored capsule. Used for state colors whose contrast
/// against the navy tile is too low for colored text (red, blue).
private struct StatusPill: View {
    let text: String
    let fill: Color
    let size: CGFloat
    init(_ text: String, fill: Color, size: CGFloat) { self.text = text; self.fill = fill; self.size = size }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.2)
            .background(Capsule().fill(fill))
    }
}

/// Hour and minute without leading zero or AM/PM, e.g. "9:30".
/// Uses the 12- or 24-hour clock of the current locale.
private func shortTime(_ date: Date) -> String {
    shortTimeFormatter.string(from: date)
}

private let shortTimeFormatter: DateFormatter = {
    let uses12Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
    let formatter = DateFormatter()
    formatter.dateFormat = uses12Hour ? "h:mm" : "H:mm"
    return formatter
}()
