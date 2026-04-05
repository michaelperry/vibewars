import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Form {
            Section("GitHub") {
                SecureField("Personal Access Token", text: $store.githubToken)
                if !store.githubUsername.isEmpty {
                    LabeledContent("Username", value: store.githubUsername)
                }
                if let error = store.githubError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Section("AI Tools") {
                ToolStatusRow(name: "Claude Code", path: "~/.claude/", active: store.claudeLocal.todayTokens > 0)
                ToolStatusRow(name: "Codex", path: "~/.codex/", active: store.codexLocal.todayTokens > 0)
                ToolStatusRow(name: "Cursor", path: "~/Library/.../Cursor/", active: store.cursorLocal.todayTokens > 0)
                ToolStatusRow(name: "Copilot", path: "~/Library/.../Code/", active: store.copilotLocal.todayTokens > 0)

                Text("AI tools are detected automatically from local files. No API keys required.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                DisclosureGroup("Advanced: Claude API Key (optional)") {
                    SecureField("API Key (for org billing data)", text: $store.claudeApiKey)
                    Text("Only needed if you want org-level cost data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let error = store.claudeError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .font(.caption)
            }

            Section("Rankings") {
                Toggle("Participate in anonymous rankings", isOn: $store.rankingsEnabled)
                Text("Only your composite VibeScore (a single number 0–100) is shared anonymously. No activity details, usernames, or API keys are ever transmitted.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if store.rankingsEnabled {
                    HStack {
                        Circle()
                            .fill(store.rankingServiceAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(store.rankingServiceAvailable ? "Connected to leaderboard" : "Leaderboard unavailable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button("Refresh Now") {
                    Task { await store.refreshAll() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 420)
    }
}

struct ToolStatusRow: View {
    let name: String
    let path: String
    let active: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(active ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text(active ? "Active" : "Not detected")
                .font(.caption)
                .foregroundColor(active ? .green : .secondary)
        }
    }
}
