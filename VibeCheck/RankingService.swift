import Foundation
import CryptoKit

actor RankingService {

    static let shared = RankingService()

    // MARK: - Configuration
    // Set these from your Supabase project dashboard (Settings > API)
    private let supabaseURL: String
    private let supabaseAnonKey: String

    private init() {
        self.supabaseURL = "https://wofxaqovazcxmcnmgrjg.supabase.co"
        self.supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndvZnhhcW92YXpjeG1jbm1ncmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0MDQ2NTEsImV4cCI6MjA5MDk4MDY1MX0.hZGBavn5FSudQXd1oTL40-Bbuu9ece77jzMOzDAuVpY"
    }

    /// Reconfigure with new Supabase credentials (called from settings or bundled config).
    func configure(url: String, anonKey: String) {
        UserDefaults.standard.set(url, forKey: "supabaseURL")
        UserDefaults.standard.set(anonKey, forKey: "supabaseAnonKey")
    }

    // MARK: - Submit Score & Get Ranking (single round trip)

    /// Submit score and retrieve rank in one call via Supabase RPC.
    func submitAndRank(score: Double, periodType: String, periodKey: String) async throws -> (rank: Int, total: Int, percentile: Double, warriorNumber: Int?) {
        let anonymousID = getAnonymousID()

        let body: [String: Any] = [
            "p_anonymous_id": anonymousID,
            "p_vibe_score": score,
            "p_period_type": periodType,
            "p_period_key": periodKey
        ]

        let result = try await rpc("submit_and_rank", body: body)

        guard let rank = result["rank"] as? Int,
              let total = result["total"] as? Int,
              let percentile = result["percentile"] as? Double
        else {
            throw RankingError.invalidResponse
        }

        let warriorNumber = result["warrior_number"] as? Int

        return (rank, total, percentile, warriorNumber)
    }

    // MARK: - Anonymous Identity

    /// Generate a stable anonymous ID from hardware UUID + salt.
    /// This never leaves the device as a raw identifier — only the hash is sent.
    private func getAnonymousID() -> String {
        // Check for cached ID first
        if let cached = UserDefaults.standard.string(forKey: "vibewars_anon_id") {
            return cached
        }

        // Generate from hardware UUID for stability across app reinstalls
        let platform = ProcessInfo.processInfo.environment["__CF_USER_TEXT_ENCODING"]
            ?? UUID().uuidString
        let machineID = Host.current().name ?? UUID().uuidString
        let raw = "vibewars_2026_\(platform)_\(machineID)"

        let hash = SHA256.hash(data: Data(raw.utf8))
        let anonymousID = hash.prefix(16).map { String(format: "%02x", $0) }.joined()

        UserDefaults.standard.set(anonymousID, forKey: "vibewars_anon_id")
        return anonymousID
    }

    // MARK: - Supabase HTTP Client

    private func rpc(_ functionName: String, body: [String: Any]) async throws -> [String: Any] {
        guard supabaseURL != "YOUR_SUPABASE_URL" else {
            throw RankingError.notConfigured
        }

        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/\(functionName)") else {
            throw RankingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RankingError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("VibeWars: Supabase error \(http.statusCode): \(msg)")
            throw RankingError.serverError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RankingError.invalidResponse
        }

        return json
    }

    // MARK: - Availability

    var isConfigured: Bool {
        supabaseURL != "YOUR_SUPABASE_URL" && supabaseAnonKey != "YOUR_SUPABASE_ANON_KEY"
    }

    func isAvailable() async -> Bool {
        guard isConfigured else { return false }
        // Health check against the score_entries table
        guard let url = URL(string: "\(supabaseURL)/rest/v1/score_entries?select=count&limit=0") else { return false }
        var request = URLRequest(url: url)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("VibeWars: Supabase health check: \(code)")
            return code == 200
        } catch {
            print("VibeWars: Supabase health check failed: \(error.localizedDescription)")
            return false
        }
    }
}

enum RankingError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase not configured"
        case .invalidURL: return "Invalid Supabase URL"
        case .invalidResponse: return "Invalid response from server"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        }
    }
}
