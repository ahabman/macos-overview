import Foundation

/// Reads session state files written by hooks/session-status.py.
enum ClaudeSessionReader {
    struct Session: Identifiable, Equatable {
        let id: String
        let cwd: String
        let state: String
        let updated: Date
        /// Bundle path of the app hosting the session; empty when unknown.
        let appPath: String
        /// Session title from the transcript; nil when the transcript has none yet.
        let title: String?

        var name: String {
            if let title, !title.isEmpty { return title }
            return cwd.isEmpty ? String(id.prefix(8)) : (cwd as NSString).lastPathComponent
        }
    }

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/overview-sessions")

    /// Files not updated for this long are treated as ended sessions
    /// (SessionEnd does not fire when a process is killed).
    static let staleAfter: TimeInterval = 12 * 3600

    static func read(now: Date = Date()) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Session? in
                guard let data = try? Data(contentsOf: url),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = obj["session_id"] as? String,
                      let state = obj["state"] as? String,
                      let updated = obj["updated"] as? Double else { return nil }
                let transcript = obj["transcript_path"] as? String ?? ""
                return Session(id: id, cwd: obj["cwd"] as? String ?? "", state: state,
                               updated: Date(timeIntervalSince1970: updated),
                               appPath: obj["app_path"] as? String ?? "",
                               title: TranscriptTitle.read(sessionID: id, transcriptPath: transcript))
            }
            .filter { now.timeIntervalSince($0.updated) < staleAfter }
            .sorted { lhs, rhs in
                let order = ["waiting": 0, "error": 1, "working": 2, "idle": 3]
                let l = order[lhs.state] ?? 4, r = order[rhs.state] ?? 4
                return l != r ? l < r : lhs.updated > rhs.updated
            }
    }
}
