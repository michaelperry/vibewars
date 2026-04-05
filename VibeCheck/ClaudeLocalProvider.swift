import Foundation

/// Reads Claude Code usage data directly from local JSONL session files.
/// No API key required — works for any Claude Code user automatically.
struct ClaudeLocalProvider: ActivityProvider {
    let providerName = "Claude Code"
    let todayTokens: Int
    let weekTokens: Int
    let todayMessages: Int
    let todayToolCalls: Int
    let todaySessions: Int
    let weekMessages: Int
}

enum ClaudeLocalReader {

    private static let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")

    private static let projectsDir = claudeDir.appendingPathComponent("projects")

    /// Scan all local Claude Code session files and aggregate usage for today and this week.
    static func readUsage() -> ClaudeLocalProvider {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        var todayTokens = 0
        var weekTokens = 0
        var todayMessages = 0
        var todayToolCalls = 0
        var todaySessions = 0
        var weekMessages = 0

        // Scan all project directories for JSONL files
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return ClaudeLocalProvider(
                todayTokens: 0, weekTokens: 0, todayMessages: 0,
                todayToolCalls: 0, todaySessions: 0, weekMessages: 0
            )
        }

        for projectDir in projectDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }

            for file in jsonlFiles {
                // Skip files not modified this week (optimization)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                      let modDate = attrs[.modificationDate] as? Date,
                      modDate >= weekStart else { continue }

                let result = parseSessionFile(file, todayStart: todayStart, weekStart: weekStart)
                todayTokens += result.todayTokens
                weekTokens += result.weekTokens
                todayMessages += result.todayMessages
                todayToolCalls += result.todayToolCalls
                weekMessages += result.weekMessages
                if result.todayMessages > 0 { todaySessions += 1 }
            }
        }

        return ClaudeLocalProvider(
            todayTokens: todayTokens, weekTokens: weekTokens,
            todayMessages: todayMessages, todayToolCalls: todayToolCalls,
            todaySessions: todaySessions, weekMessages: weekMessages
        )
    }

    private struct SessionResult {
        var todayTokens = 0
        var weekTokens = 0
        var todayMessages = 0
        var todayToolCalls = 0
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

            // Parse timestamp to determine if today or this week
            let timestamp: Date?
            if let ts = json["timestamp"] as? String {
                timestamp = parseISO8601(ts)
            } else if let msg = json["message"] as? [String: Any],
                      let ts = msg["timestamp"] as? String {
                timestamp = parseISO8601(ts)
            } else {
                timestamp = nil
            }

            let isThisWeek = timestamp.map { $0 >= weekStart } ?? true
            let isToday = timestamp.map { $0 >= todayStart } ?? false

            guard isThisWeek else { continue }

            // Extract usage from assistant messages
            if let message = json["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let tokens = input + output

                result.weekTokens += tokens
                result.weekMessages += 1

                if isToday {
                    result.todayTokens += tokens
                    result.todayMessages += 1
                }
            }

            // Count tool calls
            if isToday {
                if let type = json["type"] as? String, type == "tool_use" {
                    result.todayToolCalls += 1
                } else if let message = json["message"] as? [String: Any],
                          let content = message["content"] as? [[String: Any]] {
                    for block in content where (block["type"] as? String) == "tool_use" {
                        result.todayToolCalls += 1
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
