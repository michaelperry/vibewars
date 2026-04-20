import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var challengeCopied = false

    private var vibe: VibeState {
        ScoreEngine.vibeState(from: store.vibeScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Rank change alert
            if let event = store.latestRankChange {
                RankChangeBanner(event: event)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Vibe header
            HStack {
                Text(vibe.emoji)
                    .font(.system(size: 24))
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(vibe.label)
                            .font(.headline)
                            .foregroundColor(vibe.color)
                        if let wn = store.warriorNumber {
                            Text("Warrior #\(wn)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.vibeOrange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.vibeOrange.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text(vibe.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Update banner
            if let update = updateChecker.availableUpdate, !updateChecker.isDismissed {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("v\(update.version) available")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Update") {
                        if let url = URL(string: update.htmlURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.blue)
                    Button {
                        updateChecker.dismissUpdate()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(6)
            }

            // GitHub error banner
            if let err = store.githubError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.vibeOrange)
                        .font(.system(size: 11))
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.vibeOrange.opacity(0.08))
                .cornerRadius(6)
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
                        HStack(spacing: 4) {
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
                        StatBox(label: "Rank", value: "#\(ranking.rank) / \(ranking.total)")
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

                Button {
                    shareRankCard()
                } label: {
                    Text("Share Card")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    let message = "I'm on the VibeWars leaderboard. Think you can out-vibe me? \u{1F525}\nhttps://vibewars.dev"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                    challengeCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        challengeCopied = false
                    }
                } label: {
                    Text(challengeCopied ? "Copied, share anywhere!" : "Challenge")
                        .font(.caption)
                        .foregroundColor(challengeCopied ? .vibeGreen : nil)
                }
                .buttonStyle(.borderless)

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if store.isFetchingGitHub {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Refreshing").font(.caption)
                        }
                    } else {
                        Text("Refresh").font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.isFetchingGitHub)

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

    @MainActor
    private func shareRankCard() {
        let totalTokens = store.activityProviders.reduce(0) { $0 + $1.todayTokens }
        let cardView = RankCardView(
            vibeScore: store.vibeScore,
            ranking: store.dailyRanking,
            commitsToday: store.commitsToday,
            totalTokens: totalTokens,
            streak: store.currentStreak,
            username: store.githubUsername,
            warriorNumber: store.warriorNumber
        )
        guard let image = cardView.renderToImage() else { return }

        // Find the button's window to anchor the share picker
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            // Fallback: copy to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            return
        }

        let picker = NSSharingServicePicker(items: [image])
        let view = window.contentView ?? NSView()
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
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
