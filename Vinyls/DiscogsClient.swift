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
    private let userAgent = "VinylCollectionManager/1.0"
    private let token: String
    
    // Rate limiting
    private let queue = DispatchQueue(label: "com.vinyls.discogs.ratelimit")
    private var requestHistory: [Date] = []
    private let maxRequestsPerMinute = 60
    
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
        
        let request = createRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try handleResponse(response)
        
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
        
        let request = createRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try handleResponse(response)
        
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
        
        let request = createRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try handleResponse(response)
        
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
}

// MARK: - Helpers
private extension String {
    var trimmedSpaces: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 