import Foundation
import SQLite3

/// Reads OpenAI Codex usage data from local session files and SQLite database.
/// No API key required — detects usage automatically from ~/.codex/
struct CodexLocalProvider: ActivityProvider {
    let providerName = "Codex"
    let todayTokens: Int
    let weekTokens: Int
    let todayMessages: Int
    let todaySessions: Int
    let weekMessages: Int
}

enum CodexLocalReader {

    private static let codexDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")
    private static let sessionsDir = codexDir.appendingPathComponent("sessions")
    private static let dbPath = codexDir.appendingPathComponent("state_5.sqlite").path

    /// Read Codex usage from local files and database.
    /// Tries the SQLite threads table first (has token counts), then falls back
    /// to parsing session JSONL files (estimates tokens from message length).
    static func readUsage() -> CodexLocalProvider {
        // Try structured DB first
        let dbResult = readFromDatabase()
        if dbResult.todayTokens > 0 || dbResult.weekTokens > 0 {
            return dbResult
        }
        // Fall back to parsing session JSONL files
        return readFromSessionFiles()
    }

    // MARK: - SQLite Database Reader

    private static func readFromDatabase() -> CodexLocalProvider {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = db else {
            return empty()
        }
        defer { sqlite3_close(db) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var todayTokens = 0, weekTokens = 0
        var todayMessages = 0, todaySessions = 0, weekMessages = 0

        // Query threads table for token usage
        let sql = "SELECT tokens_used, created_at, updated_at FROM threads WHERE updated_at >= ?"
        var stmt: OpaquePointer?
        let weekISO = iso.string(from: weekStart)

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return empty()
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (weekISO as NSString).utf8String, -1, nil)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let tokens = Int(sqlite3_column_int64(stmt, 0))
            let updatedStr = String(cString: sqlite3_column_text(stmt, 2))
            let updatedAt = iso.date(from: updatedStr)

            weekTokens += tokens
            weekMessages += 1

            if let date = updatedAt, date >= todayStart {
                todayTokens += tokens
                todayMessages += 1
                todaySessions += 1
            }
        }

        return CodexLocalProvider(
            todayTokens: todayTokens, weekTokens: weekTokens,
            todayMessages: todayMessages, todaySessions: todaySessions,
            weekMessages: weekMessages
        )
    }

    // MARK: - Session JSONL Reader (Fallback)

    private static func readFromSessionFiles() -> CodexLocalProvider {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        var todayTokens = 0, weekTokens = 0
        var todayMessages = 0, todaySessions = 0, weekMessages = 0

        // Sessions are stored in ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
        guard let yearDirs = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        ) else { return empty() }

        for yearDir in yearDirs {
            guard let monthDirs = try? FileManager.default.contentsOfDirectory(
                at: yearDir, includingPropertiesForKeys: nil
            ) else { continue }

            for monthDir in monthDirs {
                guard let dayDirs = try? FileManager.default.contentsOfDirectory(
                    at: monthDir, includingPropertiesForKeys: nil
                ) else { continue }

                for dayDir in dayDirs {
                    // Quick date check from directory name (YYYY/MM/DD)
                    if let dirDate = dateFromSessionPath(yearDir: yearDir, monthDir: monthDir, dayDir: dayDir),
                       dirDate < weekStart { continue }

                    guard let files = try? FileManager.default.contentsOfDirectory(
                        at: dayDir, includingPropertiesForKeys: [.contentModificationDateKey]
                    ) else { continue }

                    let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }

                    for file in jsonlFiles {
                        let result = parseSessionFile(file, todayStart: todayStart, weekStart: weekStart)
                        todayTokens += result.todayTokens
                        weekTokens += result.weekTokens
                        todayMessages += result.todayMessages
                        weekMessages += result.weekMessages
                        if result.todayMessages > 0 { todaySessions += 1 }
                    }
                }
            }
        }

        return CodexLocalProvider(
            todayTokens: todayTokens, weekTokens: weekTokens,
            todayMessages: todayMessages, todaySessions: todaySessions,
            weekMessages: weekMessages
        )
    }

    private struct SessionResult {
        var todayTokens = 0
        var weekTokens = 0
        var todayMessages = 0
        var weekMessages = 0
    }

    private static func parseSessionFile(_ url: URL, todayStart: Date, weekStart: Date) -> SessionResult {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return SessionResult()
        }

        var result = SessionResult()
        let lines = content.components(separatedBy: "\n")

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let eventType = json["type"] as? String

            // Parse timestamp
            let timestamp: Date?
            if let ts = json["timestamp"] as? String {
                timestamp = parseISO8601(ts)
            } else {
                timestamp = nil
            }

            let isThisWeek = timestamp.map { $0 >= weekStart } ?? true
            let isToday = timestamp.map { $0 >= todayStart } ?? false

            guard isThisWeek else { continue }

            // Count response_item events (user and assistant messages)
            if eventType == "response_item",
               let payload = json["payload"] as? [String: Any] {
                let role = payload["role"] as? String
                    ?? (payload["item"] as? [String: Any])?["role"] as? String

                if role == "assistant" || role == "user" {
                    // Estimate tokens from content length (~4 chars per token)
                    let contentLength = estimateContentLength(payload)
                    let estimatedTokens = max(contentLength / 4, 1)

                    result.weekTokens += estimatedTokens
                    result.weekMessages += 1

                    if isToday {
                        result.todayTokens += estimatedTokens
                        result.todayMessages += 1
                    }
                }
            }
        }

        return result
    }

    /// Estimate character length of message content for token approximation.
    private static func estimateContentLength(_ payload: [String: Any]) -> Int {
        // Try direct content string
        if let content = payload["content"] as? String {
            return content.count
        }
        // Try content array (structured messages)
        if let contentArray = payload["content"] as? [[String: Any]] {
            return contentArray.reduce(0) { total, block in
                total + ((block["text"] as? String)?.count ?? 0)
            }
        }
        // Try nested item
        if let item = payload["item"] as? [String: Any] {
            return estimateContentLength(item)
        }
        return 0
    }

    private static func dateFromSessionPath(yearDir: URL, monthDir: URL, dayDir: URL) -> Date? {
        guard let year = Int(yearDir.lastPathComponent),
              let month = Int(monthDir.lastPathComponent),
              let day = Int(dayDir.lastPathComponent) else { return nil }
        var dc = DateComponents()
        dc.year = year; dc.month = month; dc.day = day
        dc.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: dc)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? {
            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            return basic.date(from: string)
        }()
    }

    static func empty() -> CodexLocalProvider {
        CodexLocalProvider(todayTokens: 0, weekTokens: 0, todayMessages: 0, todaySessions: 0, weekMessages: 0)
    }
}
