import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore

    private var vibe: VibeState {
        ScoreEngine.vibeState(from: store.vibeScore)
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

            // AI Tools stats (auto-detected)
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Tools")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                if store.activityProviders.isEmpty {
                    Text("No AI tool activity detected today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.activityProviders.map { $0.providerName }, id: \.self) { name in
                        ToolRow(name: name, provider: store.activityProviders.first { $0.providerName == name }!)
                    }
                }

                // Total across all tools
                let totalTokens = store.activityProviders.reduce(0) { $0 + $1.todayTokens }
                if totalTokens > 0 && store.activityProviders.count > 1 {
                    HStack {
                        Text("Total")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(formatTokens(totalTokens) + " tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }

            Divider()

            // VibeScore & Rankings
            VStack(alignment: .leading, spacing: 6) {
                Text("VibeScore")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    StatBox(label: "Score", value: "\(store.vibeScore.rounded)")
                    if let ranking = store.dailyRanking {
                        StatBox(label: "Rank", value: "#\(ranking.rank)")
                        StatBox(label: "Percentile", value: ranking.percentileText)
                    } else {
                        StatBox(label: "Rank", value: "—")
                        StatBox(label: "Percentile", value: "—")
                    }
                }

                if let ranking = store.dailyRanking {
                    Text(ranking.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if ranking.percentile >= 90 && ranking.total >= 10 {
                        Text("You are outvibing \(Int(ranking.percentile.rounded()))% of people today")
                            .font(.caption)
                            .foregroundColor(.vibeOrange)
                    }
                }

                if !store.rankingServiceAvailable && store.rankingsEnabled {
                    Text("Rankings connecting...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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

struct ToolRow: View {
    let name: String
    let provider: ActivityProvider

    var body: some View {
        HStack {
            Circle()
                .fill(Color.vibeGreen)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text(formatTokens(provider.todayTokens) + " tokens")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
