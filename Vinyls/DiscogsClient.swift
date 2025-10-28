import Foundation

// MARK: - Models
struct DiscogsSearchResult: Codable {
    let id: Int
    let title: String
    let coverImage: String
    let thumb: String?
    let artist: String?
    let genre: [String]?
    let year: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case coverImage = "cover_image"
        case thumb
        case artist
        case genre
        case year
    }
}

struct DiscogsTrack: Codable {
    let position: String
    let title: String
    let duration: String
}

struct DiscogsRelease: Codable {
    let tracklist: [DiscogsTrack]
    let notes: String?
    let genres: [String]?
    let year: Int?
}

struct DiscogsSearchResponse: Codable {
    let results: [DiscogsSearchResult]
}

// MARK: - Errors
enum DiscogsError: Error {
    case rateLimitExceeded
    case invalidResponse
    case networkError(Error)
    case noResults
    case unauthorized
}

// MARK: - Client
class DiscogsClient {
    private let baseUrl = "https://api.discogs.com"
    private let userAgent = "Vinyls/1.0 (+support@vinyls.app)"
    private let token: String
    
    // Rate limiting
    private let queue = DispatchQueue(label: "com.vinyls.discogs.ratelimit")
    private var requestHistory: [Date] = []
    private let maxRequestsPerMinute = 60
    private var nextAvailableDate: Date? = nil
    
    init(token: String) {
        self.token = token
        print("🔑 Initializing DiscogsClient with token: \(token.prefix(5))...****")
    }
    
    // MARK: - Rate Limiting
    private func waitForRateLimit() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Clean up old requests
                let now = Date()
                // If we previously computed a next-available time (e.g., after a 429), honor it here
                if let next = self.nextAvailableDate, now < next {
                    let waitTime = next.timeIntervalSince(now)
                    if waitTime > 0 {
                        Thread.sleep(forTimeInterval: waitTime)
                    }
                    self.nextAvailableDate = nil
                }
                self.requestHistory = self.requestHistory.filter { now.timeIntervalSince($0) < 60 }
                
                if self.requestHistory.count >= self.maxRequestsPerMinute {
                    // Calculate wait time based on oldest request
                    if let oldestRequest = self.requestHistory.first {
                        let waitTime = 60.0 - now.timeIntervalSince(oldestRequest)
                        if waitTime > 0 {
                            Thread.sleep(forTimeInterval: waitTime)
                        }
                    }
                }
                
                self.requestHistory.append(now)
                continuation.resume()
            }
        }
    }
    
    // Centralized request executor with 429 backoff/retry (token header path)
    private func performRequest(_ request: URLRequest, maxRetries: Int = 3) async throws -> (Data, URLResponse) {
        func header(_ response: HTTPURLResponse, _ name: String) -> String? {
            for (key, value) in response.allHeaderFields {
                if let k = key as? String, k.caseInsensitiveCompare(name) == .orderedSame {
                    return String(describing: value)
                }
            }
            return nil
        }
        var attempt = 0
        while true {
            try await waitForRateLimit()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid response type: \(response)")
                    throw DiscogsError.invalidResponse
                }
                
                print("📥 Response status code: \(httpResponse.statusCode)")
                print("📤 Response headers: \(httpResponse.allHeaderFields)")
                
                switch httpResponse.statusCode {
                case 200:
                    // Proactively pause if remaining is 0 to avoid hitting 429 on the next call
                    if let remainingStr = header(httpResponse, "x-discogs-ratelimit-remaining"),
                       let remaining = Int(remainingStr), remaining <= 0 {
                        let now = Date()
                        // No reset header provided; be conservative and wait up to 60s
                        self.nextAvailableDate = now.addingTimeInterval(60)
                    }
                    return (data, response)
                case 401:
                    print("❌ Unauthorized - Token: \(token.prefix(5))...****")
                    throw DiscogsError.unauthorized
                case 429:
                    // Determine how long to wait
                    let now = Date()
                    var waitSeconds: TimeInterval = 60 // conservative default
                    if let retryAfterStr = header(httpResponse, "Retry-After"),
                       let retryAfter = TimeInterval(retryAfterStr) {
                        waitSeconds = max(retryAfter, 1)
                    } else if let remainingStr = header(httpResponse, "x-discogs-ratelimit-remaining"),
                              let remaining = Int(remainingStr), remaining <= 0 {
                        waitSeconds = 60
                    }
                    self.nextAvailableDate = now.addingTimeInterval(waitSeconds)
                    attempt += 1
                    if attempt > maxRetries {
                        print("❌ Rate limit exceeded after \(maxRetries) retries")
                        throw DiscogsError.rateLimitExceeded
                    }
                    print("⏳ Rate limited (429). Waiting \(Int(waitSeconds))s before retry \(attempt)/\(maxRetries)...")
                    try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                    continue
                default:
                    print("❌ Unexpected status code: \(httpResponse.statusCode)")
                    throw DiscogsError.invalidResponse
                }
            } catch let error as DiscogsError {
                throw error
            } catch {
                // Bubble up network errors
                throw DiscogsError.networkError(error)
            }
        }
    }

    // GET with automatic OAuth signing when connected; falls back to token header path
    private func performGET(_ url: URL, maxRetries: Int = 3) async throws -> (Data, URLResponse) {
        // If OAuth is connected, use signed requests via OAuthSwift
        if await DiscogsAuthService.shared.isConnected {
            print("🔐 Using OAuth-signed request for: \(url.absoluteString)")
            var attempt = 0
            while true {
                try await waitForRateLimit()
                do {
                    let (data, http) = try await DiscogsAuthService.shared.performSignedGET(url: url, headers: ["User-Agent": userAgent])
                    // Handle status codes similar to token path
                    let code = http.statusCode
                    if code == 200 {
                        // Respect remaining header if present
                        let remainingStr: String? = {
                            for (key, value) in http.allHeaderFields {
                                if let k = key as? String, k.caseInsensitiveCompare("x-discogs-ratelimit-remaining") == .orderedSame {
                                    return String(describing: value)
                                }
                            }
                            return nil
                        }()
                        if let remainingStr, let remaining = Int(remainingStr), remaining <= 0 {
                            let now = Date()
                            self.nextAvailableDate = now.addingTimeInterval(60)
                        }
                        return (data, http)
                    } else if code == 401 {
                        throw DiscogsError.unauthorized
                    } else if code == 429 {
                        let now = Date()
                        var waitSeconds: TimeInterval = 60
                        let retryAfterStr: String? = {
                            for (key, value) in http.allHeaderFields {
                                if let k = key as? String, k.caseInsensitiveCompare("Retry-After") == .orderedSame {
                                    return String(describing: value)
                                }
                            }
                            return nil
                        }()
                        if let retryAfterStr, let retryAfter = TimeInterval(retryAfterStr) {
                            waitSeconds = max(retryAfter, 1)
                        } else {
                            let remainingStr2: String? = {
                                for (key, value) in http.allHeaderFields {
                                    if let k = key as? String, k.caseInsensitiveCompare("x-discogs-ratelimit-remaining") == .orderedSame {
                                        return String(describing: value)
                                    }
                                }
                                return nil
                            }()
                            if let remainingStr2, let remaining = Int(remainingStr2), remaining <= 0 {
                            waitSeconds = 60
                            }
                        }
                        self.nextAvailableDate = now.addingTimeInterval(waitSeconds)
                        attempt += 1
                        if attempt > maxRetries { throw DiscogsError.rateLimitExceeded }
                        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                        continue
                    } else {
                        throw DiscogsError.invalidResponse
                    }
                } catch let e as DiscogsError {
                    throw e
                } catch {
                    throw DiscogsError.networkError(error)
                }
            }
        }
        // Fallback: use token header path (DEBUG only)
        #if DEBUG
        if !token.isEmpty {
            print("🔑 Using token header fallback for: \(url.absoluteString)")
            let request = createRequest(for: url)
            return try await performRequest(request, maxRetries: maxRetries)
        }
        #endif
        throw DiscogsError.unauthorized
    }
    
    private func handleResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type: \(response)")
            throw DiscogsError.invalidResponse
        }
        
        print("📥 Response status code: \(httpResponse.statusCode)")
        print("📤 Response headers: \(httpResponse.allHeaderFields)")
        
        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            print("❌ Unauthorized - Token: \(token.prefix(5))...****")
            throw DiscogsError.unauthorized
        case 429:
            throw DiscogsError.rateLimitExceeded
        default:
            print("❌ Unexpected status code: \(httpResponse.statusCode)")
            throw DiscogsError.invalidResponse
        }
    }
    
    private func createRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        
        // Log redacted authorization header
        if let auth = request.value(forHTTPHeaderField: "Authorization") {
            let redactedAuth = auth.replacingOccurrences(
                of: token,
                with: "\(token.prefix(5))...****"
            )
            print("🔑 Authorization header: \(redactedAuth)")
        }
        
        return request
    }
    
    // MARK: - API Methods
    func searchRelease(artist: String, title: String) async throws -> (coverUrl: URL?, thumbUrl: URL?, releaseId: Int?) {
        try await waitForRateLimit()
        
        // Clean input similar to JS version
        let cleanArtist = artist.replacingOccurrences(of: "[&+]", with: "", options: .regularExpression)
        let cleanTitle = title
            .replacingOccurrences(of: ",.*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[&+]", with: "", options: .regularExpression)
            .trimmedSpaces
        
        var urlComponents = URLComponents(string: "\(baseUrl)/database/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "artist", value: cleanArtist),
            URLQueryItem(name: "release_title", value: cleanTitle)
        ]
        
        guard let url = urlComponents.url else {
            throw DiscogsError.invalidResponse
        }
        
        print("🔍 Searching Discogs for artist: \(cleanArtist), title: \(cleanTitle)")
        print("🌐 URL: \(url.absoluteString)")
        
        let (data, _) = try await performGET(url)
        
        let searchResponse = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
        print("📦 Found \(searchResponse.results.count) results")
        
        // Find first result with valid artwork
        for result in searchResponse.results.prefix(5) {
            let cover = result.coverImage
            let thumb = result.thumb
            
            if !cover.contains("spacer.gif") && !cover.contains("spacer.png") && cover != "https://st.discogs.com/" {
                return (
                    coverUrl: URL(string: cover),
                    thumbUrl: thumb.flatMap { URL(string: $0) },
                    releaseId: result.id
                )
            }
        }
        
        return (nil, nil, nil)
    }
    
    func getTrackList(releaseId: Int) async throws -> (tracks: [DiscogsTrack], notes: String?, genre: String?, year: String?) {
        try await waitForRateLimit()
        
        let url = URL(string: "\(baseUrl)/releases/\(releaseId)")!
        print("🔍 Fetching tracklist for release ID: \(releaseId)")
        print("🌐 URL: \(url.absoluteString)")
        
        let (data, _) = try await performGET(url)
        
        let release = try JSONDecoder().decode(DiscogsRelease.self, from: data)
        print("📦 Found \(release.tracklist.count) tracks")
        return (
            tracks: release.tracklist,
            notes: release.notes,
            genre: release.genres?.first,
            year: release.year.map { String($0) }
        )
    }
    
    func searchByBarcode(_ barcode: String) async throws -> (coverUrl: URL?, artist: String?, title: String?, genre: String?, year: String?, releaseId: Int?) {
        try await waitForRateLimit()
        
        print("🔍 Searching Discogs for barcode: \(barcode)")
        
        var urlComponents = URLComponents(string: "\(baseUrl)/database/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "barcode", value: barcode)
        ]
        
        guard let url = urlComponents.url else {
            throw DiscogsError.invalidResponse
        }
        
        print("🌐 URL: \(url.absoluteString)")
        
        let (data, _) = try await performGET(url)
        
        let searchResponse = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
        print("📦 Found \(searchResponse.results.count) results")
        
        guard let firstResult = searchResponse.results.first else {
            print("❌ No results found for barcode: \(barcode)")
            throw DiscogsError.noResults
        }
        
        // Parse the title to extract artist and album title
        let titleComponents = firstResult.title.split(separator: " - ", maxSplits: 1)
        let artist = firstResult.artist ?? (titleComponents.count > 0 ? String(titleComponents[0]) : nil)
        let title = titleComponents.count > 1 ? String(titleComponents[1]) : String(titleComponents[0])
        
        print("✅ Found match: \(artist ?? "Unknown Artist") - \(title)")
        
        return (
            coverUrl: URL(string: firstResult.coverImage),
            artist: artist,
            title: title,
            genre: firstResult.genre?.first,
            year: firstResult.year,
            releaseId: firstResult.id
        )
    }

    func searchByIdentifier(_ identifier: String) async throws -> (coverUrl: URL?, artist: String?, title: String?, genre: String?, year: String?, releaseId: Int?) {
        try await waitForRateLimit()

        print("🔍 Searching Discogs for identifier (catno): \(identifier)")

        var urlComponents = URLComponents(string: "\(baseUrl)/database/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "catno", value: identifier)
        ]

        guard let url = urlComponents.url else {
            throw DiscogsError.invalidResponse
        }

        print("🌐 URL: \(url.absoluteString)")

        let (data, _) = try await performGET(url)

        let searchResponse = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
        print("📦 Found \(searchResponse.results.count) results for identifier")

        guard let firstResult = searchResponse.results.first else {
            print("❌ No results found for identifier: \(identifier)")
            throw DiscogsError.noResults
        }

        let titleComponents = firstResult.title.split(separator: " - ", maxSplits: 1)
        let artist = firstResult.artist ?? (titleComponents.count > 0 ? String(titleComponents[0]) : nil)
        let title = titleComponents.count > 1 ? String(titleComponents[1]) : String(titleComponents[0])

        print("✅ Found match: \(artist ?? "Unknown Artist") - \(title)")

        return (
            coverUrl: URL(string: firstResult.coverImage),
            artist: artist,
            title: title,
            genre: firstResult.genre?.first,
            year: firstResult.year,
            releaseId: firstResult.id
        )
    }
}

// MARK: - Helpers
private extension String {
    var trimmedSpaces: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 