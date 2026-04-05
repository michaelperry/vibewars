import Foundation
import SQLite3

/// Reads Cursor AI editor usage from local storage.
/// Cursor stores data in ~/Library/Application Support/Cursor/ (VS Code fork)
/// and may also use ~/.cursor/ for CLI data.
struct CursorLocalProvider: ActivityProvider {
    let providerName = "Cursor"
    let todayTokens: Int
    let weekTokens: Int
    let todayMessages: Int
    let todaySessions: Int
    let weekMessages: Int
}

enum CursorLocalReader {

    private static let cursorAppSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor")
    private static let cursorHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor")

    /// Read Cursor usage from local storage.
    static func readUsage() -> CursorLocalProvider {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        var todayTokens = 0, weekTokens = 0
        var todayMessages = 0, todaySessions = 0, weekMessages = 0

        // Cursor stores chat history in its User/workspaceStorage SQLite databases
        // and in User/globalStorage for cross-workspace data
        let globalStoragePath = cursorAppSupport
            .appendingPathComponent("User/globalStorage/state.vscdb").path

        if let results = readVSCDB(path: globalStoragePath, todayStart: todayStart, weekStart: weekStart) {
            todayTokens += results.todayTokens
            weekTokens += results.weekTokens
            todayMessages += results.todayMessages
            todaySessions += results.todaySessions
            weekMessages += results.weekMessages
        }

        // Also scan workspace storage directories for per-project chat data
        let workspaceStorageDir = cursorAppSupport.appendingPathComponent("User/workspaceStorage")
        if let workspaceDirs = try? FileManager.default.contentsOfDirectory(
            at: workspaceStorageDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for dir in workspaceDirs {
                let dbPath = dir.appendingPathComponent("state.vscdb").path
                guard FileManager.default.fileExists(atPath: dbPath) else { continue }

                // Skip if not modified this week
                if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < weekStart { continue }

                if let results = readVSCDB(path: dbPath, todayStart: todayStart, weekStart: weekStart) {
                    todayTokens += results.todayTokens
                    weekTokens += results.weekTokens
                    todayMessages += results.todayMessages
                    weekMessages += results.weekMessages
                    if results.todayMessages > 0 { todaySessions += 1 }
                }
            }
        }

        return CursorLocalProvider(
            todayTokens: todayTokens, weekTokens: weekTokens,
            todayMessages: todayMessages, todaySessions: todaySessions,
            weekMessages: weekMessages
        )
    }

    private struct DBResult {
        var todayTokens = 0
        var weekTokens = 0
        var todayMessages = 0
        var todaySessions = 0
        var weekMessages = 0
    }

    /// Read from a VS Code-style state database (state.vscdb).
    /// These are SQLite databases with a key-value ItemTable containing JSON blobs.
    private static func readVSCDB(path: String, todayStart: Date, weekStart: Date) -> DBResult? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = db else { return nil }
        defer { sqlite3_close(db) }

        var result = DBResult()

        // Cursor stores AI chat data in the ItemTable under keys like:
        // "aiChat.history", "composer.history", "cursorTab.history"
        let chatKeys = [
            "aiChat.panelHistory",
            "composer.composerData",
            "aiChat.history",
            "workbench.panel.aichat.history"
        ]

        for key in chatKeys {
            let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW,
               let valueCStr = sqlite3_column_text(stmt, 0) {
                let valueStr = String(cString: valueCStr)
                guard let data = valueStr.data(using: .utf8) else { continue }

                // Parse the JSON chat history
                if let parsed = parseChatHistory(data, todayStart: todayStart, weekStart: weekStart) {
                    result.todayTokens += parsed.todayTokens
                    result.weekTokens += parsed.weekTokens
                    result.todayMessages += parsed.todayMessages
                    result.weekMessages += parsed.weekMessages
                }
            }
        }

        return result
    }

    /// Parse Cursor's chat history JSON to extract message counts and estimate tokens.
    private static func parseChatHistory(_ data: Data, todayStart: Date, weekStart: Date) -> DBResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var result = DBResult()

        // Cursor chat history can be an array of conversations or a dict with conversations
        let conversations: [[String: Any]]
        if let arr = json as? [[String: Any]] {
            conversations = arr
        } else if let dict = json as? [String: Any],
                  let tabs = dict["tabs"] as? [[String: Any]] {
            conversations = tabs
        } else if let dict = json as? [String: Any],
                  let history = dict["history"] as? [[String: Any]] {
            conversations = history
        } else {
            return nil
        }

        for convo in conversations {
            // Look for messages array
            let messages: [[String: Any]]
            if let msgs = convo["messages"] as? [[String: Any]] {
                messages = msgs
            } else if let msgs = convo["bubbles"] as? [[String: Any]] {
                messages = msgs
            } else {
                continue
            }

            for msg in messages {
                // Parse timestamp
                let timestamp: Date?
                if let ts = msg["timestamp"] as? TimeInterval {
                    timestamp = Date(timeIntervalSince1970: ts / 1000) // JS milliseconds
                } else if let ts = msg["createdAt"] as? TimeInterval {
                    timestamp = Date(timeIntervalSince1970: ts / 1000)
                } else if let ts = msg["timestamp"] as? String {
                    timestamp = parseISO8601(ts)
                } else {
                    timestamp = nil
                }

                let isThisWeek = timestamp.map { $0 >= weekStart } ?? false
                let isToday = timestamp.map { $0 >= todayStart } ?? false

                guard isThisWeek else { continue }

                // Estimate tokens from message content
                let contentLength = (msg["text"] as? String)?.count
                    ?? (msg["content"] as? String)?.count
                    ?? (msg["message"] as? String)?.count
                    ?? 0
                let estimatedTokens = max(contentLength / 4, 1)

                result.weekTokens += estimatedTokens
                result.weekMessages += 1

                if isToday {
                    result.todayTokens += estimatedTokens
                    result.todayMessages += 1
                }
            }
        }

        return result
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
}
