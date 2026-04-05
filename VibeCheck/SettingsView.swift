import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Form {
            Section("GitHub") {
                if store.isGitHubAuthenticated {
                    // Signed in state
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected as @\(store.githubUsername)")
                            .fontWeight(.medium)
                        Spacer()
                        Button("Sign Out") {
                            store.signOutGitHub()
                        }
                        .foregroundColor(.red)
                    }
                } else if store.isAuthenticatingGitHub {
                    // Waiting for user to approve in browser
                    VStack(alignment: .leading, spacing: 8) {
                        if let code = store.deviceUserCode {
                            HStack {
                                Text("Your code:")
                                    .foregroundColor(.secondary)
                                Text(code)
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .textSelection(.enabled)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(code, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .help("Copy code")
                            }
                            Text("Enter this code on GitHub, then approve access.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let uri = store.deviceVerificationURI {
                                Button("Open GitHub") {
                                    if let url = URL(string: uri) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .font(.caption)
                            }
                        }

                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for authorization...")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        Button("Cancel") {
                            store.cancelGitHubSignIn()
                        }
                        .font(.caption)
                    }
                } else {
                    // Not signed in
                    Button {
                        store.signInWithGitHub()
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                            Text("Sign in with GitHub")
                        }
                    }

                    Text("Uses GitHub Device Flow -- no token needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = store.githubAuthError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
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
