import Foundation

struct VibeScore {
    let total: Double          // typically 0–100, can exceed for power users
    let commitPoints: Double   // 0–50 (35 at anchor, log-grows past)
    let aiPoints: Double       // 0–50 (35 at anchor, log-grows past)
    let streakPoints: Double   // 0–15
    let diversityPoints: Double // 0–15

    var rounded: Int { Int(total.rounded()) }
}

enum ScorePeriod { case daily, weekly }

enum ScoreEngine {

    /// Compute a composite VibeScore from activity data.
    ///
    /// AI tokens and commits use log curves anchored so the previous "max" thresholds still yield
    /// 35 points, but power users keep climbing — 1M tokens ≈ 37, 5M ≈ 41, 10M ≈ 43. Soft cap at 50.
    ///
    /// - Parameters:
    ///   - commits: commits in the period (today for .daily, this-week for .weekly)
    ///   - providers: AI providers — daily reads todayTokens, weekly reads weekTokens
    ///   - streak: current consecutive-day streak
    ///   - period: .daily or .weekly — selects token field and adjusts anchors
    static func calculate(
        commits: Int,
        providers: [ActivityProvider],
        streak: Int,
        period: ScorePeriod = .daily
    ) -> VibeScore {
        let tokensOf: (ActivityProvider) -> Int = period == .daily
            ? { $0.todayTokens }
            : { $0.weekTokens }
        let tokenAnchor: Double = period == .daily ? 500_000 : 3_500_000  // ~7× for the week
        let commitAnchor: Double = period == .daily ? 20 : 100

        // Commits: log-scaled, 35 pts at anchor, more above. Soft cap 50.
        let commitPoints = min(logScore(value: Double(commits), anchor: commitAnchor, anchorPoints: 35.0), 50.0)

        // AI tokens: log-scaled, 35 pts at anchor, more above. Soft cap 50.
        let totalTokens = providers.reduce(0) { $0 + tokensOf($1) }
        let aiPoints = min(logScore(value: Double(totalTokens), anchor: tokenAnchor, anchorPoints: 35.0), 50.0)

        // Streak: 0–15, capped at 14 days
        let streakPoints = min(Double(streak), 14.0) / 14.0 * 15.0

        // Diversity: 0–15, bonus for using multiple AI tools (in the relevant period)
        let activeProviders = providers.filter { tokensOf($0) > 0 }.count
        let diversityPoints = min(Double(activeProviders), 3.0) / 3.0 * 15.0

        let total = commitPoints + aiPoints + streakPoints + diversityPoints

        return VibeScore(
            total: total,
            commitPoints: commitPoints,
            aiPoints: aiPoints,
            streakPoints: streakPoints,
            diversityPoints: diversityPoints
        )
    }

    /// Log-scaled score anchored so `anchor` yields exactly `anchorPoints`.
    /// Values below the anchor scale down logarithmically; values above keep growing
    /// (10× more tokens ≈ +6 pts). Caller is expected to clamp the upper end.
    private static func logScore(value: Double, anchor: Double, anchorPoints: Double) -> Double {
        guard value > 0 else { return 0 }
        return anchorPoints * log10(1 + value) / log10(1 + anchor)
    }

    /// Map a VibeScore to a display-friendly VibeState.
    static func vibeState(from score: VibeScore) -> VibeState {
        switch score.rounded {
        case 0:
            return VibeState(emoji: "👻", label: "Ghost mode", subtitle: "No activity yet — get after it", color: .vibeGray)
        case 1...25:
            return VibeState(emoji: "🌊", label: "Coasting", subtitle: "Light day so far, warming up", color: .vibeGreen)
        case 26...60:
            return VibeState(emoji: "🔒", label: "Locked in", subtitle: "Solid progress, keep the momentum", color: .vibePurple)
        default:
            return VibeState(emoji: "🔥", label: "Cooking", subtitle: "You're absolutely ripping today", color: .vibeOrange)
        }
    }
}
