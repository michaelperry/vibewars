import Foundation
import Combine
import AppKit

class AppStore: ObservableObject {

    @Published var githubToken: String {
        didSet { KeychainHelper.save(githubToken, for: "githubToken") }
    }
    @Published var claudeApiKey: String {
        didSet { KeychainHelper.save(claudeApiKey, for: "claudeApiKey") }
    }
    @Published var githubUsername: String {
        didSet { UserDefaults.standard.set(githubUsername, forKey: "githubUsername") }
    }

    // Local AI tool usage (auto-detected, no API keys needed)
    @Published var claudeLocal: ClaudeLocalProvider = ClaudeLocalProvider(
        todayTokens: 0, weekTokens: 0, todayMessages: 0,
        todayToolCalls: 0, todaySessions: 0, weekMessages: 0
    )
    @Published var codexLocal: CodexLocalProvider = CodexLocalReader.empty()
    @Published var cursorLocal: CursorLocalProvider = CursorLocalProvider(
        todayTokens: 0, weekTokens: 0, todayMessages: 0,
        todaySessions: 0, weekMessages: 0
    )
    @Published var copilotLocal: CopilotLocalProvider = CopilotLocalProvider(
        todayTokens: 0, weekTokens: 0, todayMessages: 0,
        todaySuggestions: 0, weekMessages: 0
    )

    // Claude API usage (optional, for org-level billing data)
    @Published var claudeInputTokensToday: Int = 0
    @Published var claudeOutputTokensToday: Int = 0
    @Published var claudeInputTokensWeek: Int = 0
    @Published var claudeOutputTokensWeek: Int = 0
    @Published var claudeCostToday: Double = 0
    @Published var claudeCostWeek: Double = 0
    @Published var claudeDailyUsage: [DayUsage] = []

    @Published var commitsToday: Int = 0
    @Published var commitsWeek: Int = 0
    @Published var todayCommits: [CommitItem] = []
    @Published var repoCommits: [RepoCount] = []

    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var activeDays: Set<String> = []

    @Published var isFetchingGitHub: Bool = false
    @Published var isFetchingClaude: Bool = false
    @Published var githubError: String? = nil
    @Published var claudeError: String? = nil
    @Published var lastUpdated: Date? = nil

    // GitHub OAuth Device Flow state
    @Published var isAuthenticatingGitHub: Bool = false
    @Published var deviceUserCode: String? = nil
    @Published var deviceVerificationURI: String? = nil
    @Published var githubAuthError: String? = nil
    private var authPollingTask: Task<Void, Never>? = nil

    // Scoring & Rankings
    @Published var vibeScore: VibeScore = ScoreEngine.calculate(commits: 0, providers: [], streak: 0)
    @Published var dailyRanking: RankingResult? = nil
    @Published var weeklyRanking: RankingResult? = nil
    @Published var warriorNumber: Int? = nil
    @Published var rankingsEnabled: Bool {
        didSet { UserDefaults.standard.set(rankingsEnabled, forKey: "rankingsEnabled") }
    }
    @Published var rankingServiceAvailable: Bool = false

    var activityProviders: [ActivityProvider] {
        var providers: [ActivityProvider] = []

        // Claude Code (local files)
        if claudeLocal.todayTokens > 0 || claudeLocal.weekTokens > 0 {
            providers.append(claudeLocal)
        } else if claudeInputTokensToday + claudeOutputTokensToday > 0 {
            // Fall back to API data
            providers.append(ClaudeProvider(
                todayTokens: claudeInputTokensToday + claudeOutputTokensToday,
                weekTokens: claudeInputTokensWeek + claudeOutputTokensWeek
            ))
        }

        // Codex (OpenAI)
        if codexLocal.todayTokens > 0 || codexLocal.weekTokens > 0 {
            providers.append(codexLocal)
        }

        // Cursor
        if cursorLocal.todayTokens > 0 || cursorLocal.weekTokens > 0 {
            providers.append(cursorLocal)
        }

        // GitHub Copilot
        if copilotLocal.todayTokens > 0 || copilotLocal.weekTokens > 0 {
            providers.append(copilotLocal)
        }

        return providers
    }

    private var refreshTimer: Timer?

    init() {
        self.githubToken = KeychainHelper.load("githubToken")
        self.claudeApiKey = KeychainHelper.load("claudeApiKey")
        self.githubUsername = UserDefaults.standard.string(forKey: "githubUsername") ?? ""
        self.rankingsEnabled = UserDefaults.standard.object(forKey: "rankingsEnabled") as? Bool ?? true

        // Migrate from UserDefaults (standard or sandbox container) to Keychain
        if self.githubToken.isEmpty {
            let legacy = Self.loadLegacyDefault("githubToken")
            if !legacy.isEmpty {
                self.githubToken = legacy
                KeychainHelper.save(legacy, for: "githubToken")
                print("VibeWars: Migrated GitHub token to Keychain")
            }
        }
        if self.claudeApiKey.isEmpty {
            let legacy = Self.loadLegacyDefault("claudeApiKey")
            if !legacy.isEmpty {
                self.claudeApiKey = legacy
                KeychainHelper.save(legacy, for: "claudeApiKey")
                print("VibeWars: Migrated Claude API key to Keychain")
            }
        }

        let savedWarrior = UserDefaults.standard.integer(forKey: "warriorNumber")
        if savedWarrior > 0 { self.warriorNumber = savedWarrior }

        print("VibeWars: Init — GitHub token: \(githubToken.isEmpty ? "EMPTY" : "set (\(githubToken.prefix(4))...)"), username: \(githubUsername)")
        print("VibeWars: Real home: \(RealHome.path)")

        loadPersistedData()
        scheduleRefresh()
        Task {
            await checkRankingService()
            await refreshAll()
        }
    }

    var isGitHubAuthenticated: Bool {
        !githubToken.isEmpty
    }

    func signInWithGitHub() {
        guard !isAuthenticatingGitHub else { return }
        isAuthenticatingGitHub = true
        githubAuthError = nil
        deviceUserCode = nil
        deviceVerificationURI = nil

        authPollingTask = Task {
            do {
                let deviceCode = try await GitHubAuth.requestDeviceCode()

                await MainActor.run {
                    self.deviceUserCode = deviceCode.userCode
                    self.deviceVerificationURI = deviceCode.verificationURI
                }

                // Open the browser for the user
                if let url = URL(string: deviceCode.verificationURI) {
                    await MainActor.run {
                        NSWorkspace.shared.open(url)
                    }
                }

                // Poll until the user approves
                let token = try await GitHubAuth.pollForToken(
                    deviceCode: deviceCode.deviceCode,
                    interval: deviceCode.interval,
                    expiresIn: deviceCode.expiresIn
                )

                // Fetch username
                let username = try await GitHubAuth.fetchUsername(token: token)

                await MainActor.run {
                    self.githubToken = token
                    self.githubUsername = username
                    self.isAuthenticatingGitHub = false
                    self.deviceUserCode = nil
                    self.deviceVerificationURI = nil
                }

                // Refresh data now that we have a token
                await refreshAll()
            } catch is CancellationError {
                await MainActor.run {
                    self.isAuthenticatingGitHub = false
                    self.deviceUserCode = nil
                    self.deviceVerificationURI = nil
                }
            } catch {
                await MainActor.run {
                    self.githubAuthError = error.localizedDescription
                    self.isAuthenticatingGitHub = false
                    self.deviceUserCode = nil
                    self.deviceVerificationURI = nil
                }
            }
        }
    }

    func cancelGitHubSignIn() {
        authPollingTask?.cancel()
        authPollingTask = nil
        isAuthenticatingGitHub = false
        deviceUserCode = nil
        deviceVerificationURI = nil
    }

    func signOutGitHub() {
        cancelGitHubSignIn()
        githubToken = ""
        githubUsername = ""
        commitsToday = 0
        commitsWeek = 0
        todayCommits = []
        repoCommits = []
        currentStreak = 0
        longestStreak = 0
        githubError = nil
        githubAuthError = nil
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchGitHub() }
            group.addTask { await self.readLocalProviders() }
            group.addTask { await self.fetchClaudeUsage() }
        }
        await MainActor.run {
            self.vibeScore = ScoreEngine.calculate(
                commits: self.commitsToday,
                providers: self.activityProviders,
                streak: self.currentStreak
            )
            self.lastUpdated = Date()
        }
        if rankingsEnabled && rankingServiceAvailable {
            await submitAndFetchRankings()
        }
    }

    private func checkRankingService() async {
        let available = await RankingService.shared.isAvailable()
        await MainActor.run { self.rankingServiceAvailable = available }
    }

    private func submitAndFetchRankings() async {
        let score = vibeScore.total
        let dailyKey = dayString(Date())

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let weekOfYear = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.yearForWeekOfYear, from: Date())
        let weeklyKey = "\(year)-W\(String(format: "%02d", weekOfYear))"

        do {
            // Single round trip per period: upsert score + get rank back
            async let dailyResult = RankingService.shared.submitAndRank(
                score: score, periodType: "daily", periodKey: dailyKey
            )
            async let weeklyResult = RankingService.shared.submitAndRank(
                score: score, periodType: "weekly", periodKey: weeklyKey
            )

            let (daily, weekly) = try await (dailyResult, weeklyResult)

            let prevDailyRank = UserDefaults.standard.object(forKey: "prevDailyRank_\(dailyKey)") as? Int
            let prevWeeklyRank = UserDefaults.standard.object(forKey: "prevWeeklyRank_\(weeklyKey)") as? Int

            // Persist warrior number once we get it
            let resolvedWarriorNumber = daily.warriorNumber ?? weekly.warriorNumber

            await MainActor.run {
                if let wn = resolvedWarriorNumber {
                    self.warriorNumber = wn
                    UserDefaults.standard.set(wn, forKey: "warriorNumber")
                } else if self.warriorNumber == nil {
                    // Restore from persisted value
                    let saved = UserDefaults.standard.integer(forKey: "warriorNumber")
                    if saved > 0 { self.warriorNumber = saved }
                }
                self.dailyRanking = RankingResult(
                    rank: daily.rank, total: daily.total, percentile: daily.percentile,
                    previousRank: prevDailyRank, periodType: "daily", periodKey: dailyKey,
                    warriorNumber: self.warriorNumber
                )
                self.weeklyRanking = RankingResult(
                    rank: weekly.rank, total: weekly.total, percentile: weekly.percentile,
                    previousRank: prevWeeklyRank, periodType: "weekly", periodKey: weeklyKey,
                    warriorNumber: self.warriorNumber
                )
                UserDefaults.standard.set(daily.rank, forKey: "prevDailyRank_\(dailyKey)")
                UserDefaults.standard.set(weekly.rank, forKey: "prevWeeklyRank_\(weeklyKey)")
            }
        } catch {
            print("VibeWars: Ranking error: \(error.localizedDescription)")
        }
    }

    private func scheduleRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { await self.refreshAll() }
        }
    }

    private func parseGitHubDate(_ s: String) -> Date? {
        let clean = s.replacingOccurrences(of: "T", with: "-")
                     .replacingOccurrences(of: ":", with: "-")
                     .replacingOccurrences(of: "Z", with: "")
        let parts = clean.components(separatedBy: "-")
        guard parts.count == 6,
              let year  = Int(parts[0]),
              let month = Int(parts[1]),
              let day   = Int(parts[2]),
              let hour  = Int(parts[3]),
              let min   = Int(parts[4]),
              let sec   = Int(parts[5]) else { return nil }
        var dc = DateComponents()
        dc.year = year; dc.month = month; dc.day = day
        dc.hour = hour; dc.minute = min; dc.second = sec
        dc.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: dc)
    }

    func fetchGitHub() async {
        guard !githubToken.isEmpty else { return }
        await MainActor.run { isFetchingGitHub = true; githubError = nil }

        do {
            let user = try await ghRequest("https://api.github.com/user")
            guard let username = user["login"] as? String else {
                await MainActor.run { self.githubError = "Could not resolve GitHub username"; self.isFetchingGitHub = false }
                return
            }
            await MainActor.run { self.githubUsername = username }

            var events = try await ghRequestArray("https://api.github.com/users/\(username)/events?per_page=100")
            if let org = try? await ghRequestArray("https://api.github.com/users/\(username)/events/orgs?per_page=100") {
                events.append(contentsOf: org)
            }

            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.current
            let now = Date()
            let todayStart = cal.startOfDay(for: now)
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

            var todayList: [CommitItem] = []
            var weekTotal = 0
            var repoMap: [String: Int] = [:]
            var activeDaySet: Set<String> = loadActiveDays()

            for event in events {
                guard let type = event["type"] as? String, type == "PushEvent",
                      let createdStr = event["created_at"] as? String,
                      let createdAt = parseGitHubDate(createdStr),
                      let payload = event["payload"] as? [String: Any],
                      let repoObj = event["repo"] as? [String: Any],
                      let repoName = repoObj["name"] as? String
                else { continue }

                let commitCount = payload["size"] as? Int ?? (payload["commits"] as? [[String: Any]])?.count ?? 1
                let commitMessages = payload["commits"] as? [[String: Any]] ?? []

                if createdAt >= weekStart {
                    weekTotal += commitCount
                    repoMap[repoName, default: 0] += commitCount
                    activeDaySet.insert(dayString(createdAt))

                    if createdAt >= todayStart {
                        if commitMessages.isEmpty {
                            let shortRepo = repoName.components(separatedBy: "/").last ?? repoName
                            todayList.append(CommitItem(
                                message: "\(commitCount) commit\(commitCount == 1 ? "" : "s")",
                                repo: shortRepo,
                                time: createdAt
                            ))
                        } else {
                            for commit in commitMessages {
                                let msg = (commit["message"] as? String ?? "").components(separatedBy: "\n").first ?? ""
                                todayList.append(CommitItem(
                                    message: String(msg.prefix(72)),
                                    repo: repoName.components(separatedBy: "/").last ?? repoName,
                                    time: createdAt
                                ))
                            }
                        }
                    }
                }
            }

            let sortedRepos = repoMap.map { RepoCount(name: $0.key.components(separatedBy: "/").last ?? $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
            let (streak, longest) = calculateStreaks(activeDays: activeDaySet)

            await MainActor.run {
                self.commitsToday = todayList.count
                self.commitsWeek = weekTotal
                self.todayCommits = todayList.sorted { $0.time > $1.time }
                self.repoCommits = sortedRepos
                self.activeDays = activeDaySet
                self.currentStreak = streak
                self.longestStreak = longest
                self.isFetchingGitHub = false
                self.saveActiveDays(activeDaySet)
            }
        } catch {
            await MainActor.run { self.githubError = error.localizedDescription; self.isFetchingGitHub = false }
        }
    }

    /// Read all local AI tool usage — no API keys required.
    /// Scans ~/.claude/, ~/.codex/, Cursor, and VS Code extension storage.
    private func readLocalProviders() async {
        let claude = ClaudeLocalReader.readUsage()
        let codex = CodexLocalReader.readUsage()
        let cursor = CursorLocalReader.readUsage()
        let copilot = CopilotLocalReader.readUsage()
        await MainActor.run {
            self.claudeLocal = claude
            self.codexLocal = codex
            self.cursorLocal = cursor
            self.copilotLocal = copilot
        }
    }

    func fetchClaudeUsage() async {
        guard !claudeApiKey.isEmpty else { return }
        await MainActor.run { isFetchingClaude = true; claudeError = nil }

        do {
            let now = Date()
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.current
            let todayStart = cal.startOfDay(for: now)
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

            // Format dates for API — ISO8601 UTC
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            iso.timeZone = TimeZone(secondsFromGMT: 0)

            let startingAt = iso.string(from: weekStart)
            let endingAt = iso.string(from: now)

            // Correct Anthropic usage API endpoint
            let urlStr = "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=\(startingAt)&ending_at=\(endingAt)&bucket_width=1d"
            guard let url = URL(string: urlStr) else { return }

            var request = URLRequest(url: url)
            request.setValue(claudeApiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            print("VibeWars: Claude API status \(http.statusCode)")
            let rawStr = String(data: data, encoding: .utf8) ?? ""
            print("VibeWars: Claude API response: \(rawStr.prefix(300))")

            if http.statusCode == 200 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let buckets = json["data"] as? [[String: Any]] {

                    var inputToday = 0, outputToday = 0
                    var inputWeek = 0, outputWeek = 0
                    var dailyList: [DayUsage] = []

                    let dayFormatter = DateFormatter()
                    dayFormatter.dateFormat = "yyyy-MM-dd"

                    for bucket in buckets {
                        guard let startStr = bucket["start_time"] as? String,
                              let bucketDate = parseGitHubDate(startStr) else { continue }

                        // Sum all model usage in this bucket
                        var bucketInput = 0
                        var bucketOutput = 0

                        if let usage = bucket["usage"] as? [[String: Any]] {
                            for entry in usage {
                                bucketInput += entry["input_tokens"] as? Int ?? 0
                                bucketOutput += entry["output_tokens"] as? Int ?? 0
                            }
                        } else {
                            // Flat structure
                            bucketInput = bucket["input_tokens"] as? Int ?? 0
                            bucketOutput = bucket["output_tokens"] as? Int ?? 0
                        }

                        inputWeek += bucketInput
                        outputWeek += bucketOutput

                        dailyList.append(DayUsage(
                            date: bucketDate,
                            label: dayFormatter.string(from: bucketDate),
                            inputTokens: bucketInput,
                            outputTokens: bucketOutput
                        ))

                        if bucketDate >= todayStart {
                            inputToday += bucketInput
                            outputToday += bucketOutput
                        }
                    }

                    // Sonnet 4 pricing: $3/M input, $15/M output
                    let costToday = Double(inputToday) / 1_000_000 * 3.0 + Double(outputToday) / 1_000_000 * 15.0
                    let costWeek = Double(inputWeek) / 1_000_000 * 3.0 + Double(outputWeek) / 1_000_000 * 15.0

                    await MainActor.run {
                        self.claudeInputTokensToday = inputToday
                        self.claudeOutputTokensToday = outputToday
                        self.claudeInputTokensWeek = inputWeek
                        self.claudeOutputTokensWeek = outputWeek
                        self.claudeCostToday = costToday
                        self.claudeCostWeek = costWeek
                        self.claudeDailyUsage = dailyList.sorted { $0.date < $1.date }
                        self.isFetchingClaude = false
                    }
                }
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run {
                    self.claudeError = "API error \(http.statusCode): \(msg)"
                    self.isFetchingClaude = false
                }
            }
        } catch {
            await MainActor.run { self.claudeError = error.localizedDescription; self.isFetchingClaude = false }
        }
    }

    private func calculateStreaks(activeDays: Set<String>) -> (current: Int, longest: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var current = 0, longest = 0
        var date = Date()
        while true {
            if activeDays.contains(dayString(date)) { current += 1; date = calendar.date(byAdding: .day, value: -1, to: date)! }
            else { break }
        }
        let sorted = activeDays.compactMap { formatter.date(from: $0) }.sorted()
        var run = 0, prev: Date? = nil
        for day in sorted {
            run = (prev.map { calendar.dateComponents([.day], from: $0, to: day).day == 1 } == true) ? run + 1 : 1
            longest = max(longest, run)
            prev = day
        }
        return (current, longest)
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    /// Load a value from UserDefaults, checking both standard and sandbox container locations.
    private static func loadLegacyDefault(_ key: String) -> String {
        // Standard location
        if let val = UserDefaults.standard.string(forKey: key), !val.isEmpty {
            return val
        }
        // Sandbox container location (from when app ran sandboxed)
        let containerPlist = RealHome.appending("Library/Containers/com.michaelperry.VibeWars/Data/Library/Preferences/com.michaelperry.VibeWars.plist")
        if let dict = NSDictionary(contentsOf: containerPlist),
           let val = dict[key] as? String, !val.isEmpty {
            return val
        }
        return ""
    }

    private func loadActiveDays() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "activeDays") ?? []) }
    private func saveActiveDays(_ days: Set<String>) { UserDefaults.standard.set(Array(days), forKey: "activeDays") }
    private func loadPersistedData() {
        activeDays = Set(UserDefaults.standard.stringArray(forKey: "activeDays") ?? [])
        let (s, l) = calculateStreaks(activeDays: activeDays)
        currentStreak = s; longestStreak = l
    }

    private func ghRequest(_ urlString: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func ghRequestArray(_ urlString: String) async throws -> [[String: Any]] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }
}

struct CommitItem: Identifiable {
    let id = UUID()
    let message: String
    let repo: String
    let time: Date
    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: time)
    }
}

struct RepoCount: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct DayUsage: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let inputTokens: Int
    let outputTokens: Int
    var totalTokens: Int { inputTokens + outputTokens }
    var shortLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

