import SwiftUI
import AppKit

struct RankCardView: View {
    let vibeScore: VibeScore
    let ranking: RankingResult?
    let commitsToday: Int
    let totalTokens: Int
    let streak: Int
    let username: String

    private let cardWidth: CGFloat = 600
    private let cardHeight: CGFloat = 400

    private let bgColor = Color(hex: "#0e0e0e")
    private let green = Color(hex: "#1D9E75")
    private let orange = Color(hex: "#EF9F27")
    private let purple = Color(hex: "#7F77DD")

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(bgColor)

            // Subtle gradient overlay
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [purple.opacity(0.15), green.opacity(0.1), bgColor.opacity(0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 0) {
                // Header
                HStack {
                    // App icon from bundle
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("⚔️")
                            .font(.system(size: 32))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VibeWars")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        if !username.isEmpty {
                            Text("@\(username)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    // Vibe state emoji
                    Text(ScoreEngine.vibeState(from: vibeScore).emoji)
                        .font(.system(size: 36))
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)

                Spacer().frame(height: 24)

                // Score prominently
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(vibeScore.rounded)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(green)
                    Text("/ 100")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }

                Text("VibeScore")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(2)

                Spacer().frame(height: 28)

                // Stats row
                HStack(spacing: 0) {
                    cardStat(
                        value: ranking.map { "#\($0.rank) / \($0.total)" } ?? "—",
                        label: "Rank",
                        color: orange
                    )
                    cardDivider()
                    cardStat(
                        value: ranking?.percentileText ?? "—",
                        label: "Percentile",
                        color: purple
                    )
                    cardDivider()
                    cardStat(
                        value: "\(commitsToday)",
                        label: "Commits",
                        color: green
                    )
                    cardDivider()
                    cardStat(
                        value: formatTokens(totalTokens),
                        label: "AI Tokens",
                        color: purple
                    )
                    cardDivider()
                    cardStat(
                        value: "\(streak)d",
                        label: "Streak",
                        color: orange
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                // Footer
                Text("vibewars.dev")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 20)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private func cardStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func cardDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 36)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Render to NSImage

    @MainActor
    func renderToImage() -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0  // Retina
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cardWidth, height: cardHeight))
    }
}
