import Foundation
import SQLite3

/// Reads GitHub Copilot usage from VS Code extension storage.
/// Copilot stores accepted/rejected suggestion counts and chat history
/// in VS Code's globalStorage directory.
struct CopilotLocalProvider: ActivityProvider {
    let providerName = "Copilot"
    let todayTokens: Int
    let weekTokens: Int
    let todayMessages: Int      // chat messages
    let todaySuggestions: Int    // code completions accepted
    let weekMessages: Int
}

enum CopilotLocalReader {

    private static let vscodeAppSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Code")
    private static let copilotChatStorage = vscodeAppSupport
        .appendingPathComponent("User/globalStorage/github.copilot-chat")
    private static let copilotStorage = vscodeAppSupport
        .appendingPathComponent("User/globalStorage/github.copilot")

    /// Read Copilot usage from VS Code extension storage.
    static func readUsage() -> CopilotLocalProvider {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        var todayTokens = 0, weekTokens = 0
        var todayMessages = 0, weekMessages = 0
        var todaySuggestions = 0

        // Read Copilot Chat history
        let chatResult = readCopilotChat(todayStart: todayStart, weekStart: weekStart)
        todayTokens += chatResult.todayTokens
        weekTokens += chatResult.weekTokens
        todayMessages += chatResult.todayMessages
        weekMessages += chatResult.weekMessages

        // Read inline completion telemetry from VS Code state DB
        let completionResult = readCompletionTelemetry(todayStart: todayStart, weekStart: weekStart)
        todaySuggestions += completionResult.todaySuggestions
        todayTokens += completionResult.todaySuggestions * 50 // ~50 tokens per accepted completion
        weekTokens += completionResult.weekSuggestions * 50

        return CopilotLocalProvider(
            todayTokens: todayTokens, weekTokens: weekTokens,
            todayMessages: todayMessages, todaySuggestions: todaySuggestions,
            weekMessages: weekMessages
        )
    }

    // MARK: - Chat History

    private struct ChatResult {
        var todayTokens = 0
        var weekTokens = 0
        var todayMessages = 0
        var weekMessages = 0
    }

    private static func readCopilotChat(todayStart: Date, weekStart: Date) -> ChatResult {
        var result = ChatResult()

        // Copilot Chat stores conversations in JSON files
        let chatHistoryFile = copilotChatStorage.appendingPathComponent("chatHistory.json")
        guard let data = try? Data(contentsOf: chatHistoryFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return result }

        for conversation in json {
            guard let messages = conversation["messages"] as? [[String: Any]] else { continue }

            for msg in messages {
                let timestamp: Date?
                if let ts = msg["timestamp"] as? TimeInterval {
                    timestamp = Date(timeIntervalSince1970: ts / 1000)
                } else if let ts = msg["createdAt"] as? String {
                    timestamp = parseISO8601(ts)
                } else {
                    timestamp = nil
                }

                let isThisWeek = timestamp.map { $0 >= weekStart } ?? false
                let isToday = timestamp.map { $0 >= todayStart } ?? false

                guard isThisWeek else { continue }

                let contentLength = (msg["content"] as? String)?.count
                    ?? (msg["text"] as? String)?.count ?? 0
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

    // MARK: - Inline Completion Telemetry

    private struct CompletionResult {
        var todaySuggestions = 0
        var weekSuggestions = 0
    }

    private static func readCompletionTelemetry(todayStart: Date, weekStart: Date) -> CompletionResult {
        var result = CompletionResult()

        // VS Code stores extension telemetry in the global state DB
        let dbPath = vscodeAppSupport.appendingPathComponent("User/globalStorage/state.vscdb").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return result }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = db else { return result }
        defer { sqlite3_close(db) }

        // Look for Copilot telemetry data in the ItemTable
        let telemetryKeys = [
            "github.copilot.telemetry",
            "github.copilot.usage",
            "github.copilot.acceptedCount"
        ]

        for key in telemetryKeys {
            let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW,
               let valueCStr = sqlite3_column_text(stmt, 0) {
                let valueStr = String(cString: valueCStr)

                // Parse accepted suggestion count
                if let count = Int(valueStr) {
                    // Simple count — attribute proportionally
                    result.weekSuggestions += count
                    result.todaySuggestions += count // Can't distinguish day from total
                } else if let data = valueStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Structured telemetry
                    if let accepted = json["acceptedCount"] as? Int {
                        result.weekSuggestions += accepted
                    }
                    if let todayAccepted = json["todayAcceptedCount"] as? Int {
                        result.todaySuggestions += todayAccepted
                    }
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
