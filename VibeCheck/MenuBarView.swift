import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore

    private var vibe: VibeState {
        let commits = store.commitsToday
        let streak = store.currentStreak
        let hasTokens = (store.claudeInputTokensToday + store.claudeOutputTokensToday) > 0

        var score = commits
        if streak >= 3 { score += 2 }
        if streak >= 7 { score += 3 }
        if hasTokens { score += 2 }

        switch score {
        case 0:
            return VibeState(emoji: "👻", label: "Ghost mode", subtitle: "No activity yet — get after it", color: Color(hex: "#888780"))
        case 1...3:
            return VibeState(emoji: "🌊", label: "Coasting", subtitle: "Light day so far, warming up", color: Color(hex: "#1D9E75"))
        case 4...9:
            return VibeState(emoji: "🔒", label: "Locked in", subtitle: "Solid progress, keep the momentum", color: Color(hex: "#7F77DD"))
        default:
            return VibeState(emoji: "🔥", label: "Cooking", subtitle: "You're absolutely ripping today", color: Color(hex: "#EF9F27"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Vibe header
            HStack {
                Text(vibe.emoji)
                    .font(.system(size: 24))
                VStack(alignment: .leading) {
                    Text(vibe.label)
                        .font(.headline)
                        .foregroundColor(vibe.color)
                    Text(vibe.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // GitHub stats
            VStack(alignment: .leading, spacing: 6) {
                Text("GitHub")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    StatBox(label: "Today", value: "\(store.commitsToday)")
                    StatBox(label: "This Week", value: "\(store.commitsWeek)")
                    StatBox(label: "Streak", value: "\(store.currentStreak)d")
                }

                if !store.todayCommits.isEmpty {
                    ForEach(store.todayCommits.prefix(5)) { commit in
                        HStack {
                            Text(commit.message)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(commit.repo)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Claude stats
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    StatBox(label: "Today", value: formatTokens(store.claudeInputTokensToday + store.claudeOutputTokensToday))
                    StatBox(label: "Cost Today", value: String(format: "$%.2f", store.claudeCostToday))
                    StatBox(label: "Cost Week", value: String(format: "$%.2f", store.claudeCostWeek))
                }
            }

            Divider()

            HStack {
                if let updated = store.lastUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await store.refreshAll() }
                }
                .buttonStyle(.borderless)
                .font(.caption)

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Text("Settings")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
