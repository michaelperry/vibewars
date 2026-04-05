import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let vibe = ScoreEngine.vibeState(from: store.vibeScore)
        HStack(spacing: 6) {
            Text(vibe.emoji)
                .font(.system(size: 13))

            Text(vibe.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vibe.color)

            Text("·")
                .foregroundColor(.secondary)
                .font(.system(size: 11))

            Text("\(store.commitsToday)c")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            if let wn = store.warriorNumber {
                Text("·")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Text("#\(wn)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.vibeOrange)
            }

            if store.currentStreak > 1 {
                Text("·")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Text("\(store.currentStreak)d")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.vibeOrange)
            }
        }
        .padding(.horizontal, 4)
    }
}
