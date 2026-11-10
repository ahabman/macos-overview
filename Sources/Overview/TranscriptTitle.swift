import Foundation

/// Reads a session's title from its Claude Code transcript
/// (~/.claude/projects/<project>/<session_id>.jsonl).
///
/// Claude Code appends a `{"type":"custom-title","customTitle":...}` record on each
/// turn; the latest one is the title the Claude desktop app shows. Only the end
/// of the file is read, and results are cached until the file changes.
enum TranscriptTitle {
    private static var cache: [String: (modified: Date, title: String?)] = [:]
    private static let tailBytes = 512 * 1024

    static func read(sessionID: String, transcriptPath: String) -> String? {
        guard let path = transcriptPath.isEmpty ? findTranscript(sessionID: sessionID) : transcriptPath,
              let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return nil }
        if let cached = cache[path], cached.modified == modified { return cached.title }
        let title = latestTitle(path: path)
        cache[path] = (modified, title)
        return title
    }

    private static func latestTitle(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"custom-title\"") {
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               object["type"] as? String == "custom-title",
               let title = object["customTitle"] as? String {
                return title
            }
        }
        return nil
    }

    /// Fallback for status files written before the hook recorded transcript_path.
    private static func findTranscript(sessionID: String) -> String? {
        let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return folders
            .map { projects.appendingPathComponent($0).appendingPathComponent(sessionID + ".jsonl").path }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
