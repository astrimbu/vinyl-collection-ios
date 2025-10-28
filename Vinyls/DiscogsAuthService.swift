import Foundation
import Security
import OSLog
#if canImport(OAuthSwift)
import OAuthSwift
#endif

@MainActor
final class DiscogsAuthService: ObservableObject {
    static let shared = DiscogsAuthService()

    private let logger = Logger(subsystem: "com.vinyls.app", category: "DiscogsAuth")

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var username: String = ""

    private let callbackScheme = "vinyls"
    private let callbackURLString = "vinyls://oauth-callback/discogs"

    // Keychain keys
    private let kcService = "com.vinyls.app.discogs"
    private let kcAccountToken = "accessToken"
    private let kcAccountSecret = "accessTokenSecret"
    private let kcAccountUsername = "username"

    #if canImport(OAuthSwift)
    private var oauth: OAuth1Swift?
    #endif

    private init() {
        // Load from Keychain if present
        let token = Self.keychainRead(service: kcService, account: kcAccountToken)
        let secret = Self.keychainRead(service: kcService, account: kcAccountSecret)
        let name = Self.keychainRead(service: kcService, account: kcAccountUsername) ?? ""
        self.username = name
        self.isConnected = !(token?.isEmpty ?? true) && !(secret?.isEmpty ?? true)
        #if canImport(OAuthSwift)
        if isConnected, let token, let secret {
            self.oauth = Self.makeOAuth(consumerKey: API.discogsConsumerKey, consumerSecret: API.discogsConsumerSecret)
            self.oauth?.client.credential.oauthToken = token
            self.oauth?.client.credential.oauthTokenSecret = secret
        }
        #endif
    }

    // MARK: - Public API
    #if canImport(OAuthSwift)
    func connect() {
        guard !API.discogsConsumerKey.isEmpty, !API.discogsConsumerSecret.isEmpty else {
            logger.error("Missing consumer key/secret; cannot start OAuth")
            return
        }
        let oauth = Self.makeOAuth(consumerKey: API.discogsConsumerKey, consumerSecret: API.discogsConsumerSecret)
        self.oauth = oauth

        // Use ASWebAuthenticationSession under the hood
        oauth.authorize(withCallbackURL: callbackURLString) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let (credential, _, _)):
                    Self.keychainWrite(service: self?.kcService ?? "", account: self?.kcAccountToken ?? "", data: credential.oauthToken)
                    Self.keychainWrite(service: self?.kcService ?? "", account: self?.kcAccountSecret ?? "", data: credential.oauthTokenSecret)
                    self?.isConnected = true
                    // Fetch identity for username
                    await self?.refreshIdentity()
                case .failure(let error):
                    self?.logger.error("OAuth authorize failed: \(error.localizedDescription)")
                }
            }
        }
    }
    #else
    func connect() { /* OAuthSwift not available at build time */ }
    #endif

    func disconnect() {
        #if canImport(OAuthSwift)
        oauth = nil
        #endif
        Self.keychainDelete(service: kcService, account: kcAccountToken)
        Self.keychainDelete(service: kcService, account: kcAccountSecret)
        Self.keychainDelete(service: kcService, account: kcAccountUsername)
        username = ""
        isConnected = false
    }

    func handleOpenURL(_ url: URL) {
        #if canImport(OAuthSwift)
        OAuthSwift.handle(url: url)
        #endif
    }

    #if canImport(OAuthSwift)
    func performSignedGET(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        guard let oauth else { throw NSError(domain: "DiscogsAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]) }
        return try await withCheckedThrowingContinuation { continuation in
            oauth.client.get(url.absoluteString, headers: headers) { result in
                switch result {
                case .success(let response):
                    if let http = response.response as? HTTPURLResponse {
                        continuation.resume(returning: (response.data, http))
                    } else {
                        continuation.resume(throwing: NSError(domain: "DiscogsAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    #else
    // Fallback stub when OAuthSwift is not yet available; prompts caller to use token flow
    func performSignedGET(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        throw NSError(domain: "DiscogsAuth", code: -10, userInfo: [NSLocalizedDescriptionKey: "OAuth not available; please add OAuthSwift dependency"]) 
    }
    #endif

    func currentCredentials() -> (token: String, secret: String)? {
        guard let t = Self.keychainRead(service: kcService, account: kcAccountToken),
              let s = Self.keychainRead(service: kcService, account: kcAccountSecret),
              !t.isEmpty, !s.isEmpty else { return nil }
        return (t, s)
    }

    // MARK: - Identity
    @discardableResult
    func refreshIdentity() async -> String? {
        #if canImport(OAuthSwift)
        guard let url = URL(string: "https://api.discogs.com/oauth/identity") else { return nil }
        do {
            let (data, http) = try await performSignedGET(url: url, headers: Self.defaultHeaders())
            guard http.statusCode == 200 else { return nil }
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let username = dict["username"] as? String {
                self.username = username
                Self.keychainWrite(service: kcService, account: kcAccountUsername, data: username)
                return username
            }
        } catch {
            logger.error("Failed to fetch identity: \(error.localizedDescription)")
        }
        #endif
        return nil
    }

    // MARK: - Headers
    static func defaultHeaders() -> [String: String] {
        [
            "User-Agent": "Vinyls/1.0 (+support@vinyls.app)"
        ]
    }

    // MARK: - OAuth factory
    #if canImport(OAuthSwift)
    private static func makeOAuth(consumerKey: String, consumerSecret: String) -> OAuth1Swift {
        let oauth = OAuth1Swift(
            consumerKey: consumerKey,
            consumerSecret: consumerSecret,
            requestTokenUrl: "https://api.discogs.com/oauth/request_token",
            authorizeUrl: "https://www.discogs.com/oauth/authorize",
            accessTokenUrl: "https://api.discogs.com/oauth/access_token"
        )
        // ASWebAuthenticationSession handler is used by default on iOS if available
        return oauth
    }
    #endif

    // MARK: - Keychain helpers
    private static func keychainQuery(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    private static func keychainWrite(service: String, account: String, data: String) -> Bool {
        let encoded = data.data(using: .utf8) ?? Data()
        var query = keychainQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = encoded
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func keychainRead(service: String, account: String) -> String? {
        var query = keychainQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func keychainDelete(service: String, account: String) -> Bool {
        let query = keychainQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
}


