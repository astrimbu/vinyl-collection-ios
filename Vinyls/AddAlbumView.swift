import SwiftUI
import OSLog

struct AddAlbumView: View {
    @StateObject private var discogsService = DiscogsService.shared
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger(subsystem: "com.vinyls.app", category: "AddAlbum")
    
    @State private var artist = ""
    @State private var title = ""
    @State private var isSearching = false
    @State private var artwork: UIImage?
    @State private var tracks: [DiscogsTrack] = []
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Album Details")) {
                    TextField("Artist", text: $artist)
                        .onChange(of: artist) { oldValue, newValue in
                            logger.debug("Artist changed to: \(newValue)")
                            debounceSearch()
                        }
                    TextField("Album Title", text: $title)
                        .onChange(of: title) { oldValue, newValue in
                            logger.debug("Title changed to: \(newValue)")
                            debounceSearch()
                        }
                    
                    if isSearching {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                
                if let artwork = artwork {
                    Section(header: Text("Artwork")) {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 200)
                    }
                }
                
                if !tracks.isEmpty {
                    Section(header: Text("Tracks")) {
                        ForEach(tracks, id: \.position) { track in
                            HStack {
                                Text(track.position)
                                    .foregroundColor(.secondary)
                                Text(track.title)
                                Spacer()
                                if !track.duration.isEmpty {
                                    Text(track.duration)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Album")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") {
                    // TODO: Save album to database
                    dismiss()
                }
            )
        }
    }
    
    private func debounceSearch() {
        // Cancel any existing search task
        searchTask?.cancel()
        
        // Create a new search task with a delay
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            if !Task.isCancelled {
                await searchDiscogs()
            }
        }
    }
    
    private func searchDiscogs() async {
        guard !artist.isEmpty && !title.isEmpty else {
            logger.debug("Search skipped - artist or title is empty")
            return
        }
        
        logger.debug("Starting Discogs search for '\(artist) - \(title)'")
        isSearching = true
        
        let (artworkUrl, fetchedTracks) = await discogsService.fetchAlbumDetails(
            artist: artist,
            title: title
        )
        
        if let url = artworkUrl {
            logger.debug("Found artwork URL: \(url.absoluteString)")
            do {
                let imageData = try await discogsService.loadArtwork(for: url)
                artwork = UIImage(data: imageData)
                logger.debug("Successfully loaded artwork")
            } catch {
                logger.error("Failed to load artwork: \(error.localizedDescription)")
            }
        } else {
            logger.debug("No artwork URL found")
        }
        
        tracks = fetchedTracks
        logger.debug("Found \(fetchedTracks.count) tracks")
        isSearching = false
    }
} 