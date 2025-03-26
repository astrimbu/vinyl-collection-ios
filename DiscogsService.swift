import Foundation
import OSLog

@MainActor
class DiscogsService: ObservableObject {
    private let client: DiscogsClient
    private let logger = Logger(subsystem: "com.vinyls.app", category: "Discogs")
    
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    init() {
        print("🎵 DiscogsService init called")
        logger.debug("Initializing DiscogsService")
        do {
            print("🎵 Creating DiscogsClient with token: \(String(describing: API.discogsToken.prefix(5)))...")
            self.client = DiscogsClient(token: API.discogsToken)
            print("🎵 DiscogsService initialized successfully")
            logger.debug("DiscogsService initialized successfully with token")
        } catch {
            print("❌ Failed to initialize DiscogsService: \(error)")
            logger.error("Failed to initialize DiscogsService: \(error.localizedDescription)")
            fatalError("Failed to initialize DiscogsService: \(error)")
        }
    }
    
    func fetchAlbumDetails(artist: String, title: String) async -> (artwork: URL?, tracks: [DiscogsTrack]) {
        print("🎵 fetchAlbumDetails called for: \(artist) - \(title)")
        isLoading = true
        error = nil
        
        logger.debug("Fetching album details for '\(artist) - \(title)'")
        
        do {
            let (coverUrl, _, releaseId) = try await client.searchRelease(artist: artist, title: title)
            print("🎵 Search results - Cover URL: \(coverUrl?.absoluteString ?? "none"), Release ID: \(releaseId ?? 0)")
            logger.debug("Search results - Cover URL: \(coverUrl?.absoluteString ?? "none"), Release ID: \(releaseId ?? 0)")
            
            if let releaseId = releaseId {
                let tracks = try await client.getTrackList(releaseId: releaseId)
                print("🎵 Found \(tracks.count) tracks")
                logger.debug("Found \(tracks.count) tracks")
                isLoading = false
                return (coverUrl, tracks)
            }
            
            print("🎵 No release ID found")
            logger.debug("No release ID found")
            isLoading = false
            return (nil, [])
        } catch {
            print("❌ Error fetching album details: \(error)")
            logger.error("Error fetching album details: \(error.localizedDescription)")
            self.error = error
            isLoading = false
            return (nil, [])
        }
    }
    
    // Helper method to load album artwork
    func loadArtwork(for url: URL) async throws -> Data {
        print("🎵 Loading artwork from URL: \(url.absoluteString)")
        logger.debug("Loading artwork from URL: \(url.absoluteString)")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            print("🎵 Successfully loaded artwork data: \(data.count) bytes")
            logger.debug("Successfully loaded artwork data: \(data.count) bytes")
            return data
        } catch {
            print("❌ Failed to load artwork: \(error)")
            logger.error("Failed to load artwork: \(error.localizedDescription)")
            throw error
        }
    }
} 