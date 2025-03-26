import Foundation

// MARK: - Models
struct DiscogsSearchResult: Codable {
    let id: Int
    let title: String
    let coverImage: String
    let thumb: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case coverImage = "cover_image"
        case thumb
    }
}

struct DiscogsTrack: Codable {
    let position: String
    let title: String
    let duration: String
}

struct DiscogsRelease: Codable {
    let tracklist: [DiscogsTrack]
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
        
        var request = URLRequest(url: url)
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw DiscogsError.rateLimitExceeded
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DiscogsError.invalidResponse
        }
        
        let searchResponse = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
        
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
    
    func getTrackList(releaseId: Int) async throws -> [DiscogsTrack] {
        try await waitForRateLimit()
        
        let url = URL(string: "\(baseUrl)/releases/\(releaseId)")!
        var request = URLRequest(url: url)
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DiscogsError.invalidResponse
        }
        
        let release = try JSONDecoder().decode(DiscogsRelease.self, from: data)
        return release.tracklist
    }
}

// MARK: - Helpers
private extension String {
    var trimmedSpaces: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 