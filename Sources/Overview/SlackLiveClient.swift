import Foundation

/// A Slack conversation with messages received since the Slack Dock badge was last clear.
struct SlackUnread: Identifiable, Equatable {
    enum Kind { case dm, groupDM, channel }

    let id: String          // Slack conversation ID
    let kind: Kind
    var sender: String      // display name of the latest sender
    var channelName: String // channel name without "#"; empty for DMs
    var latest: Date
    var count: Int

    var title: String {
        switch kind {
        case .dm: return sender
        case .groupDM: return "\(sender) (group DM)"
        case .channel: return "\(sender) in #\(channelName)"
        }
    }
}

/// Receives Slack message events over Socket Mode and records who wrote where.
///
/// Tokens are read from the Keychain, service `com.bamfhealth.overview.slack`:
/// account `token` holds the user token (xoxp-), account `app-token` the
/// app-level token (xapp-) with `connections:write`.
///
/// Message text is inspected only to detect an @-mention of the current user
/// and is never stored or displayed.
@MainActor
final class SlackLiveClient {
    enum State: Equatable {
        case notConfigured
        case connecting
        case connected
        case failed(String)
    }

    static let keychainService = "com.bamfhealth.overview.slack"

    private(set) var state: State = .notConfigured { didSet { if state != oldValue { log("state \(state)"); onChange?() } } }
    private(set) var unread: [String: SlackUnread] = [:] { didSet { onChange?() } }
    var onChange: (() -> Void)?

    private var userToken = ""
    private var appToken = ""
    private var selfID: String?
    private var userNames: [String: String] = [:]
    private var channelNames: [String: String] = [:]
    private var socket: URLSessionWebSocketTask?
    private var reconnectScheduled = false
    private let session = URLSession(configuration: .default)

    func start() {
        // Keychain reads can block on an access prompt (macOS asks again after each
        // rebuild of an ad-hoc signed app), so read off the main thread.
        Task {
            let service = Self.keychainService
            let tokens = await Task.detached { () -> (String, String)? in
                // Read the app token first: a missing item does not trigger a Keychain prompt.
                guard let app = Keychain.read(service: service, account: "app-token"),
                      let user = Keychain.read(service: service, account: "token") else { return nil }
                return (app, user)
            }.value
            guard let (app, user) = tokens else {
                state = .notConfigured
                return
            }
            appToken = app
            userToken = user
            await connect()
        }
    }

    func clearUnread() {
        if !unread.isEmpty { unread = [:] }
    }

    // MARK: - Connection

    private func connect() async {
        reconnectScheduled = false
        state = .connecting
        do {
            if selfID == nil {
                let auth = try await api("auth.test", token: userToken)
                selfID = auth["user_id"] as? String
            }
            let open = try await api("apps.connections.open", token: appToken)
            guard let address = open["url"] as? String, let url = URL(string: address) else {
                throw SlackError("apps.connections.open returned no url")
            }
            let task = session.webSocketTask(with: url)
            socket = task
            task.resume()
            receive(on: task)
            ping(task)
        } catch {
            state = .failed(String(describing: error))
            scheduleReconnect(after: 30)
        }
    }

    private func scheduleReconnect(after seconds: UInt64) {
        guard !reconnectScheduled else { return }
        reconnectScheduled = true
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            await connect()
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                    self.scheduleReconnect(after: 5)
                case .success(let message):
                    if case .string(let text) = message { self.handle(text, on: task) }
                    self.receive(on: task)
                }
            }
        }
    }

    /// Detects a dead connection; Slack does not always close the socket cleanly.
    private func ping(_ task: URLSessionWebSocketTask) {
        Task {
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard socket === task else { return }
            task.sendPing { [weak self] error in
                Task { @MainActor in
                    guard let self, self.socket === task else { return }
                    if error != nil { self.scheduleReconnect(after: 5) } else { self.ping(task) }
                }
            }
        }
    }

    private func handle(_ text: String, on task: URLSessionWebSocketTask) {
        guard let envelope = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        if let envelopeID = envelope["envelope_id"] as? String {
            let ack = (try? JSONSerialization.data(withJSONObject: ["envelope_id": envelopeID])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            task.send(.string(ack)) { _ in }
        }
        switch envelope["type"] as? String {
        case "hello":
            state = .connected
        case "disconnect":
            scheduleReconnect(after: 0)
        case "events_api":
            if let event = (envelope["payload"] as? [String: Any])?["event"] as? [String: Any] {
                Task { await process(event) }
            }
        default:
            break
        }
    }

    // MARK: - Events

    private func process(_ event: [String: Any]) async {
        guard event["type"] as? String == "message",
              event["subtype"] == nil,
              let user = event["user"] as? String, user != selfID,
              let channel = event["channel"] as? String,
              let channelType = event["channel_type"] as? String else { return }

        let kind: SlackUnread.Kind
        switch channelType {
        case "im": kind = .dm
        case "mpim": kind = .groupDM
        case "channel", "group":
            // Channel messages count only when they @-mention the current user,
            // matching what Slack's Dock badge counts by default.
            let text = event["text"] as? String ?? ""
            guard let selfID, text.contains("<@\(selfID)>") else { return }
            kind = .channel
        default:
            return
        }

        let sender = await userName(user)
        let channelName = kind == .channel ? await self.channelName(channel) : ""
        let ts = Double(event["ts"] as? String ?? "") ?? Date().timeIntervalSince1970

        var entry = unread[channel] ?? SlackUnread(id: channel, kind: kind, sender: sender, channelName: channelName,
                                                   latest: .distantPast, count: 0)
        entry.sender = sender
        entry.latest = Date(timeIntervalSince1970: ts)
        entry.count += 1
        unread[channel] = entry
    }

    private func userName(_ id: String) async -> String {
        if let cached = userNames[id] { return cached }
        let response = try? await api("users.info", token: userToken, params: ["user": id])
        let user = response?["user"] as? [String: Any]
        let profile = user?["profile"] as? [String: Any]
        let name = [profile?["display_name"], profile?["real_name"], user?["name"]]
            .compactMap { $0 as? String }
            .first { !$0.isEmpty } ?? id
        userNames[id] = name
        return name
    }

    private func channelName(_ id: String) async -> String {
        if let cached = channelNames[id] { return cached }
        let response = try? await api("conversations.info", token: userToken, params: ["channel": id])
        let name = (response?["channel"] as? [String: Any])?["name"] as? String ?? id
        channelNames[id] = name
        return name
    }

    // MARK: - Web API

    private struct SlackError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func api(_ method: String, token: String, params: [String: String] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackError("\(method): invalid response")
        }
        guard object["ok"] as? Bool == true else {
            throw SlackError("\(method): \(object["error"] as? String ?? "unknown error")")
        }
        return object
    }

    private func log(_ line: String) {
        DebugLog.write("slack \(line)")
    }
}
