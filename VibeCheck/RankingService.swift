import Foundation
import CryptoKit

actor RankingService {

    static let shared = RankingService()

    // MARK: - Configuration
    // Set these from your Supabase project dashboard (Settings > API)
    private let supabaseURL: String
    private let supabaseAnonKey: String

    private init() {
        self.supabaseURL = UserDefaults.standard.string(forKey: "supabaseURL")
            ?? "YOUR_SUPABASE_URL"
        self.supabaseAnonKey = UserDefaults.standard.string(forKey: "supabaseAnonKey")
            ?? "YOUR_SUPABASE_ANON_KEY"
    }

    /// Reconfigure with new Supabase credentials (called from settings or bundled config).
    func configure(url: String, anonKey: String) {
        UserDefaults.standard.set(url, forKey: "supabaseURL")
        UserDefaults.standard.set(anonKey, forKey: "supabaseAnonKey")
    }

    // MARK: - Submit Score & Get Ranking (single round trip)

    /// Submit score and retrieve rank in one call via Supabase RPC.
    func submitAndRank(score: Double, periodType: String, periodKey: String) async throws -> (rank: Int, total: Int, percentile: Double) {
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

        return (rank, total, percentile)
    }

    // MARK: - Anonymous Identity

    /// Generate a stable anonymous ID from hardware UUID + salt.
    /// This never leaves the device as a raw identifier — only the hash is sent.
    private func getAnonymousID() -> String {
        // Check for cached ID first
        if let cached = UserDefaults.standard.string(forKey: "vibecheck_anon_id") {
            return cached
        }

        // Generate from hardware UUID for stability across app reinstalls
        let platform = ProcessInfo.processInfo.environment["__CF_USER_TEXT_ENCODING"]
            ?? UUID().uuidString
        let machineID = Host.current().name ?? UUID().uuidString
        let raw = "vibecheck_2026_\(platform)_\(machineID)"

        let hash = SHA256.hash(data: Data(raw.utf8))
        let anonymousID = hash.prefix(16).map { String(format: "%02x", $0) }.joined()

        UserDefaults.standard.set(anonymousID, forKey: "vibecheck_anon_id")
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
            print("VibeCheck: Supabase error \(http.statusCode): \(msg)")
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
        // Quick health check
        guard let url = URL(string: "\(supabaseURL)/rest/v1/") else { return false }
        var request = URLRequest(url: url)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
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
