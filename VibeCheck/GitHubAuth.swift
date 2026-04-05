import Foundation

/// Handles GitHub OAuth Device Flow authentication.
/// See: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
class GitHubAuth {

    /// Replace with your GitHub OAuth App's Client ID.
    /// Create one at: https://github.com/settings/applications/new
    /// - Set "Device flow" to enabled in the OAuth App settings.
    static let clientID = "Ov23lig3fPiaXgtrHFLZ"

    /// Scopes requested from the user.
    static let scopes = "repo read:user"

    struct DeviceCodeResponse {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let expiresIn: Int
        let interval: Int
    }

    enum AuthError: LocalizedError {
        case networkError(String)
        case expired
        case denied
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return "Network error: \(msg)"
            case .expired: return "Authorization request expired. Please try again."
            case .denied: return "Authorization was denied."
            case .invalidResponse(let msg): return "Invalid response: \(msg)"
            }
        }
    }

    /// Step 1: Request a device code from GitHub.
    static func requestDeviceCode() async throws -> DeviceCodeResponse {
        guard let url = URL(string: "https://github.com/login/device/code") else {
            throw AuthError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientID)&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AuthError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(text)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verificationURI = json["verification_uri"] as? String,
              let expiresIn = json["expires_in"] as? Int,
              let interval = json["interval"] as? Int else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AuthError.invalidResponse(text)
        }

        return DeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            expiresIn: expiresIn,
            interval: interval
        )
    }

    /// Step 2: Poll GitHub until the user approves (or the code expires).
    /// Returns the access token on success.
    static func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> String {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            throw AuthError.networkError("Invalid URL")
        }

        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        let pollInterval = max(interval, 5) // GitHub requires at least 5s

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let token = json["access_token"] as? String {
                return token
            }

            if let error = json["error"] as? String {
                switch error {
                case "authorization_pending":
                    // User hasn't approved yet — keep polling
                    continue
                case "slow_down":
                    // Back off by 5 extra seconds
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                case "expired_token":
                    throw AuthError.expired
                case "access_denied":
                    throw AuthError.denied
                default:
                    let desc = json["error_description"] as? String ?? error
                    throw AuthError.invalidResponse(desc)
                }
            }
        }

        throw AuthError.expired
    }

    /// Fetch the authenticated user's login name.
    static func fetchUsername(token: String) async throws -> String {
        guard let url = URL(string: "https://api.github.com/user") else {
            throw AuthError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String else {
            throw AuthError.invalidResponse("Could not read username")
        }

        return login
    }
}
