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

                Toggle("Include private repos", isOn: $store.privateReposEnabled)
                    .onChange(of: store.privateReposEnabled) { _ in
                        if store.isGitHubAuthenticated {
                            // Need to re-authenticate with new scope
                            store.signOutGitHub()
                            store.signInWithGitHub()
                        }
                    }
                Text(store.privateReposEnabled
                     ? "Repo scope granted — private commits are tracked. We never read your code."
                     : "Only public activity is tracked. Enable to count private repo commits.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

            Section("Repositories") {
                if store.isGitHubAuthenticated {
                    if store.availableRepos.isEmpty {
                        Text("No repos discovered yet. Pull to refresh.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Button("Select All") {
                                for repo in store.availableRepos {
                                    if !store.isRepoEnabled(repo) {
                                        store.toggleRepo(repo)
                                    }
                                }
                            }
                            .font(.caption)
                            Button("Deselect All") {
                                for repo in store.availableRepos {
                                    if store.isRepoEnabled(repo) {
                                        store.toggleRepo(repo)
                                    }
                                }
                            }
                            .font(.caption)
                        }

                        ForEach(store.availableRepos, id: \.self) { repoName in
                            let shortName = repoName.components(separatedBy: "/").last ?? repoName
                            let weekCount = store.repoCommits.first(where: { $0.name == repoName })?.count ?? 0
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { store.isRepoEnabled(repoName) },
                                    set: { _ in store.toggleRepo(repoName) }
                                )) {
                                    HStack {
                                        Text(shortName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("\(weekCount) this week")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                    }
                } else {
                    Text("Sign in to GitHub to see your repos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

            Section("About") {
                HStack {
                    Text("VibeWars")
                        .fontWeight(.medium)
                    Spacer()
                    Text("v\(UpdateChecker.shared.currentVersion)")
                        .foregroundColor(.secondary)
                }
                .font(.caption)

                Button("Check for Updates") {
                    Task { await UpdateChecker.shared.checkForUpdate() }
                }
                .font(.caption)

                if let update = UpdateChecker.shared.availableUpdate {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Version \(update.version) is available")
                            .font(.caption)
                        Spacer()
                        Button("Download") {
                            if let url = URL(string: update.htmlURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                } else if UpdateChecker.shared.lastChecked != nil {
                    Text("You're up to date.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 640)
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
