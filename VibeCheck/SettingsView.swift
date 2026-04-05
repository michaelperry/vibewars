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

            Section("Claude API") {
                SecureField("API Key", text: $store.claudeApiKey)
                if let error = store.claudeError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Section {
                Button("Refresh Now") {
                    Task { await store.refreshAll() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
