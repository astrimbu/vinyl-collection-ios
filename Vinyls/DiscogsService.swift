import Foundation
import OSLog

@MainActor
class DiscogsService: ObservableObject {
    static let shared = DiscogsService()
    
    private let client: DiscogsClient
    private let logger = Logger(subsystem: "com.vinyls.app", category: "Discogs")
    
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // Queue for managing background tasks
    private let backgroundQueue = DispatchQueue(label: "com.vinyls.discogs.background", qos: .userInitiated)
    private var backgroundTasks: [String: Task<Void, Never>] = [:]
    
    private init() {
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
    
    func fetchAlbumDetails(artist: String, title: String) async -> (artwork: URL?, tracks: [DiscogsTrack], genre: String?, year: String?, notes: String?) {
        print("🎵 fetchAlbumDetails called for: \(artist) - \(title)")
        isLoading = true
        error = nil
        
        logger.debug("Fetching album details for '\(artist) - \(title)'")
        
        do {
            let (coverUrl, _, releaseId) = try await client.searchRelease(artist: artist, title: title)
            print("🎵 Search results - Cover URL: \(coverUrl?.absoluteString ?? "none"), Release ID: \(releaseId ?? 0)")
            logger.debug("Search results - Cover URL: \(coverUrl?.absoluteString ?? "none"), Release ID: \(releaseId ?? 0)")
            
            if let releaseId = releaseId {
                let (tracks, notes, genre, year) = try await client.getTrackList(releaseId: releaseId)
                print("🎵 Found \(tracks.count) tracks")
                logger.debug("Found \(tracks.count) tracks")
                isLoading = false
                return (coverUrl, tracks, genre, year, notes)
            }
            
            print("🎵 No release ID found")
            logger.debug("No release ID found")
            isLoading = false
            return (nil, [], nil, nil, nil)
        } catch {
            print("❌ Error fetching album details: \(error)")
            logger.error("Error fetching album details: \(error.localizedDescription)")
            self.error = error
            isLoading = false
            return (nil, [], nil, nil, nil)
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
    
    func searchByBarcode(_ barcode: String) async -> (coverUrl: URL?, artist: String?, title: String?, genre: String?, year: String?, releaseId: Int?) {
        isLoading = true
        error = nil
        
        logger.debug("Searching for barcode: \(barcode)")
        
        do {
            let (coverUrl, artist, title, genre, year, releaseId) = try await client.searchByBarcode(barcode)
            isLoading = false
            return (coverUrl, artist, title, genre, year, releaseId)
        } catch DiscogsError.noResults {
            logger.debug("No results found for barcode: \(barcode)")
            isLoading = false
            // Don't set error for no results - it's a valid state
            return (nil, nil, nil, nil, nil, nil)
        } catch DiscogsError.rateLimitExceeded {
            logger.error("Rate limit exceeded while searching barcode: \(barcode)")
            self.error = DiscogsError.rateLimitExceeded
            isLoading = false
            return (nil, nil, nil, nil, nil, nil)
        } catch {
            logger.error("Error searching barcode: \(error.localizedDescription)")
            self.error = error
            isLoading = false
            return (nil, nil, nil, nil, nil, nil)
        }
    }
    
    func startBackgroundSearch(for barcode: String, completion: @escaping (URL?, String?, String?, String?, String?, [DiscogsTrack]?, String?) -> Void) {
        // Cancel existing task for this barcode if it exists
        backgroundTasks[barcode]?.cancel()
        
        // Create new task
        let task = Task {
            // Add random delay between 0.5 and 2 seconds to help with rate limiting
            try? await Task.sleep(nanoseconds: UInt64.random(in: 500_000_000...2_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            let result = await searchByBarcode(barcode)
            
            if let releaseId = result.releaseId {
                // If we have a release ID, fetch additional details
                let details = await fetchAlbumDetails(artist: result.artist ?? "", title: result.title ?? "")
                
                await MainActor.run {
                    completion(
                        result.coverUrl,
                        result.artist,
                        result.title,
                        details.genre ?? result.genre,
                        details.year ?? result.year,
                        details.tracks,
                        details.notes
                    )
                }
            } else {
                await MainActor.run {
                    completion(
                        result.coverUrl,
                        result.artist,
                        result.title,
                        result.genre,
                        result.year,
                        nil,
                        nil
                    )
                }
            }
        }
        
        backgroundTasks[barcode] = task
    }
    
    func cancelSearch(for barcode: String) {
        backgroundTasks[barcode]?.cancel()
        backgroundTasks[barcode] = nil
    }
} 