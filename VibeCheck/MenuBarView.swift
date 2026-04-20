import SwiftUI
import AppKit

// MARK: - Main popover

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var period: Period = .today
    @State private var challengeCopied = false

    enum Period: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "This Week"
        var id: String { rawValue }
    }

    private var vibe: VibeState { ScoreEngine.vibeState(from: store.vibeScore) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let event = store.latestRankChange {
                RankChangeBanner(event: event)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            headerRow

            if let update = updateChecker.availableUpdate, !updateChecker.isDismissed {
                updateBanner(update)
            }

            if let err = store.githubError {
                errorBanner(err)
            }

            Divider()
            HeatmapView(activeDays: store.activeDays)
            heatmapLegend
            periodToggle
            statsGrid
            punchline
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text(vibe.emoji).font(.system(size: 28))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(vibe.label)
                        .font(.headline)
                        .foregroundColor(vibe.color)
                    if let wn = store.warriorNumber {
                        Text("WARRIOR #\(wn)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.vibeOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
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
    }

    // MARK: banners

    private func updateBanner(_ update: AppUpdate) -> some View {
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

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.vibeOrange)
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.vibeOrange.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: heatmap legend

    private var heatmapLegend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.vibeOrange.opacity(0.15 + Double(i) * 0.25))
                    .frame(width: 9, height: 9)
            }
            Text("More")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(store.activeDays.count) active days · \(store.longestStreak)d longest")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    // MARK: period toggle

    private var periodToggle: some View {
        HStack(spacing: 14) {
            ForEach(Array(Period.allCases.enumerated()), id: \.element.id) { idx, p in
                if idx > 0 {
                    Text("·").foregroundColor(.secondary)
                }
                Button {
                    period = p
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 12, weight: period == p ? .bold : .regular, design: .monospaced))
                        .foregroundColor(period == p ? .vibeOrange : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: stats grid (two-col, monospace)

    private var statsGrid: some View {
        let isToday = period == .today
        let totalTokens = store.activityProviders.reduce(0) {
            $0 + (isToday ? $1.todayTokens : $1.weekTokens)
        }
        let commits = isToday ? store.commitsToday : store.commitsWeek
        let score = (isToday ? store.vibeScore : store.weeklyVibeScore).rounded
        let ranking = isToday ? store.dailyRanking : store.weeklyRanking
        let messages = isToday ? store.claudeLocal.todayMessages : store.claudeLocal.weekMessages
        let favTool = bestProvider(isToday: isToday)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                StatLine(label: "Favorite tool", value: favTool ?? "—")
                Spacer()
                StatLine(label: "Total tokens", value: formatTokens(totalTokens))
            }
            HStack(alignment: .top) {
                StatLine(label: "Commits", value: "\(commits)")
                Spacer()
                StatLine(label: "VibeScore", value: "\(score)")
            }
            HStack(alignment: .top) {
                StatLine(label: "Messages", value: "\(messages)")
                Spacer()
                StatLine(label: "Current streak", value: "\(store.currentStreak)d")
            }
            HStack(alignment: .top) {
                if let r = ranking {
                    StatLine(label: "Rank", value: "#\(r.rank) / \(r.total)")
                } else {
                    StatLine(label: "Rank", value: "—")
                }
                Spacer()
                if let r = ranking {
                    StatLine(label: "Percentile", value: r.percentileText)
                } else {
                    StatLine(label: "Percentile", value: "—")
                }
            }
        }
    }

    // MARK: punchline

    private var punchline: some View {
        Text(quip())
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.vibePurple)
            .padding(.top, 2)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func quip() -> String {
        if let r = store.dailyRanking, r.percentile >= 90, r.total >= 10 {
            return "You are out-vibing \(Int(r.percentile.rounded()))% of warriors today"
        }
        if store.currentStreak >= 7 {
            return "Your \(store.currentStreak)-day streak is harder to break than most habits"
        }
        if store.commitsToday >= 10 {
            return "\(store.commitsToday) commits today — you're in the zone"
        }
        let tokens = store.activityProviders.reduce(0) { $0 + $1.todayTokens }
        if tokens >= 1_000_000 {
            return "1M+ tokens today — that's a small library you've prompted"
        }
        if !store.rankingServiceAvailable && store.rankingsEnabled {
            return "Rankings connecting…"
        }
        return "Vibe coding never stops"
    }

    private func bestProvider(isToday: Bool) -> String? {
        store.activityProviders
            .max { (isToday ? $0.todayTokens : $0.weekTokens) < (isToday ? $1.todayTokens : $1.weekTokens) }?
            .providerName
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button { shareRankCard() } label: {
                Text("Share Card").font(.caption)
            }
            .buttonStyle(.borderless)

            Button {
                let message = "I'm on the VibeWars leaderboard. Think you can out-vibe me? \u{1F525}\nhttps://vibewars.dev"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
                challengeCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { challengeCopied = false }
            } label: {
                Text(challengeCopied ? "Copied!" : "Challenge")
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
                SettingsLink { Text("Settings").font(.caption) }
                    .buttonStyle(.borderless)
            }
        }
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

        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            return
        }

        let picker = NSSharingServicePicker(items: [image])
        let view = window.contentView ?? NSView()
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

// MARK: - Heatmap

struct HeatmapView: View {
    let activeDays: Set<String>

    private let weeks = 26       // last ~6 months
    private let cellSize: CGFloat = 10
    private let cellGap: CGFloat = 2

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            dayLabels
            grid
        }
    }

    private var dayLabels: some View {
        VStack(spacing: cellGap) {
            ForEach(0..<7, id: \.self) { row in
                Text(label(forRow: row))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var grid: some View {
        HStack(spacing: cellGap) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: cellGap) {
                    ForEach(0..<7, id: \.self) { row in
                        let day = day(forWeek: week, row: row)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(forDay: day))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func label(forRow row: Int) -> String {
        switch row {
        case 0: return "Mon"
        case 2: return "Wed"
        case 4: return "Fri"
        default: return ""
        }
    }

    /// Map (week, row) to a "yyyy-MM-dd" string. Bottom-right cell is today;
    /// columns go back week-by-week, rows are Mon..Sun within each.
    private func day(forWeek week: Int, row: Int) -> String {
        let cal = Calendar.current
        let now = Date()
        let daysAgo = (weeks - 1 - week) * 7 + (6 - row)
        let date = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return Self.dayFormatter.string(from: date)
    }

    private func color(forDay day: String) -> Color {
        if activeDays.contains(day) {
            return Color.vibeOrange.opacity(0.85)
        }
        return Color.vibeOrange.opacity(0.08)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()
}

// MARK: - Stat line

struct StatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.vibeOrange)
        }
    }
}

// MARK: - Helpers

private func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
    if count >= 1_000     { return String(format: "%.1fK", Double(count) / 1_000) }
    return "\(count)"
}
