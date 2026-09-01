import Foundation

enum HHAuthConfig {
    static let placeholderAccessToken = "REPLACE_WITH_YOUR_HH_APPLICATION_TOKEN"
    static let appAccessToken = placeholderAccessToken
    static var configuredAccessToken: String? { normalizedAccessToken(appAccessToken) }

    static func normalizedAccessToken(_ token: String?) -> String? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              token != placeholderAccessToken else { return nil }
        return token
    }
}

protocol HHAccessTokenProviding: Sendable { var accessToken: String? { get } }

struct HHDefaultAccessTokenProvider: HHAccessTokenProviding {
    var accessToken: String? { HHAuthConfig.configuredAccessToken }
}
