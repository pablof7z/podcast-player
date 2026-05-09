import Foundation

// MARK: - Authorization & token DTOs

/// Single in-flight authorization. The `state` and `codeVerifier` must
/// survive across the web-auth callback for PKCE + CSRF validation.
struct BYOKPendingAuthorization {
    let provider: String
    let authorizationURL: URL
    let redirectURI: String
    let clientID: String
    let state: String
    let codeVerifier: String
}

struct BYOKTokenRequest: Encodable {
    let grantType = "authorization_code"
    let code: String
    let codeVerifier: String
    let clientID: String
    let redirectURI: String

    private enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case codeVerifier = "code_verifier"
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
    }
}

struct BYOKTokenResponse: Decodable, Sendable {
    let tokenType: String
    let provider: String
    let apiKey: String
    let keyID: String?
    let keyLabel: String?
    let appName: String?
    let issuedAt: Int?

    private enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case provider
        case apiKey = "api_key"
        case keyID = "key_id"
        case keyLabel = "key_label"
        case appName = "app_name"
        case issuedAt = "issued_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        provider = try container.decode(String.self, forKey: .provider).lowercased()
        apiKey = try container.decode(String.self, forKey: .apiKey)
        keyID = try container.decodeIfPresent(String.self, forKey: .keyID)
        keyLabel = try container.decodeIfPresent(String.self, forKey: .keyLabel)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        issuedAt = try container.decodeIfPresent(Int.self, forKey: .issuedAt)
    }
}

struct BYOKTokenErrorResponse: Decodable {
    let error: String?
}

// MARK: - Errors

enum BYOKConnectError: LocalizedError {
    case accessDenied
    case authenticationFailed
    case cancelled
    case invalidAuthorizationURL
    case invalidCallback
    case invalidTokenResponse
    case missingCode
    case randomGenerationFailed
    case serverRejectedToken(error: String?)
    case stateMismatch
    case tokenExchangeFailed
    case unexpectedProvider

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Access was denied in BYOK."
        case .authenticationFailed:
            "BYOK authentication could not be completed."
        case .cancelled:
            "BYOK connection was cancelled."
        case .invalidAuthorizationURL:
            "BYOK authorization URL could not be created."
        case .invalidCallback:
            "BYOK returned an unexpected callback."
        case .invalidTokenResponse:
            "BYOK returned an invalid token response."
        case .missingCode:
            "BYOK did not return an authorization code."
        case .randomGenerationFailed:
            "Secure random generation failed."
        case .serverRejectedToken(let error):
            if let error, !error.isEmpty {
                "BYOK rejected the token exchange: \(error)"
            } else {
                "BYOK rejected the token exchange."
            }
        case .stateMismatch:
            "BYOK returned an invalid state."
        case .tokenExchangeFailed:
            "BYOK token exchange failed."
        case .unexpectedProvider:
            "BYOK returned a credential for the wrong provider."
        }
    }
}

// MARK: - Helpers

extension Data {
    /// RFC 4648 §5 base64url encoding (no padding) — required by OAuth PKCE.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
