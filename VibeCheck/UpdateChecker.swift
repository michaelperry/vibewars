import Foundation
import Combine
import AppKit

struct AppUpdate {
    let version: String
    let htmlURL: String
    let releaseNotes: String
}

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var availableUpdate: AppUpdate? = nil
    @Published var lastChecked: Date? = nil
    @Published var isChecking: Bool = false

    private let repoOwner = "michaelperry"
    private let repoName = "vibewars"
    private let checkInterval: TimeInterval = 4 * 60 * 60 // 4 hours
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func startPeriodicChecks() {
        Task { await checkForUpdate() }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { _ in
            Task { @MainActor in await self.checkForUpdate() }
        }
    }

    func checkForUpdate() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false; lastChecked = Date() }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let notes = json["body"] as? String ?? ""

            if isNewer(remote: remoteVersion, local: currentVersion) {
                self.availableUpdate = AppUpdate(version: remoteVersion, htmlURL: htmlURL, releaseNotes: notes)
                print("VibeWars: Update available: v\(remoteVersion)")
            } else {
                self.availableUpdate = nil
            }
        } catch {
            print("VibeWars: Update check failed: \(error.localizedDescription)")
        }
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    func dismissUpdate() {
        if let update = availableUpdate {
            UserDefaults.standard.set(update.version, forKey: "dismissedUpdateVersion")
        }
        availableUpdate = nil
    }

    var isDismissed: Bool {
        guard let update = availableUpdate else { return false }
        return UserDefaults.standard.string(forKey: "dismissedUpdateVersion") == update.version
    }
}
