import Foundation

struct RankingResult {
    let rank: Int
    let total: Int
    let percentile: Double     // 0–100, e.g. 97.0 means "outvibing 97% of people"
    let previousRank: Int?     // nil on first submission
    let periodType: String     // "daily" or "weekly"
    let periodKey: String      // "2026-04-05" or "2026-W14"

    var rankDelta: Int? {
        guard let prev = previousRank else { return nil }
        return prev - rank // positive = moved up
    }

    var subtitle: String {
        if let delta = rankDelta {
            if delta > 0 {
                return "You moved up \(delta) spot\(delta == 1 ? "" : "s") today"
            } else if delta < 0 {
                return "You dropped \(abs(delta)) spot\(abs(delta) == 1 ? "" : "s") — keep pushing"
            } else {
                return "Holding steady at #\(rank)"
            }
        }
        if total == 1 {
            return "First one here — you're the vibe pioneer"
        }
        if total < 10 {
            return "Early adopter — \(total) vibe coders and counting"
        }
        return "Welcome to the leaderboard"
    }

    var percentileText: String {
        if total <= 1 { return "Top 1%" }
        let topPercent = max(Int((Double(rank) / Double(total) * 100).rounded()), 1)
        return "Top \(topPercent)%"
    }
}
