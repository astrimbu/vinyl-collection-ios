print("AlbumDetailView.swift is being compiled")  // Debug print at file level

import SwiftUI
import OSLog

struct Album {
    let id: UUID
    var artist: String
    var title: String
    var artworkUrl: URL?
    var tracks: [DiscogsTrack]
    
    init(id: UUID = UUID(), artist: String, title: String) {
        print("Creating Album: \(artist) - \(title)")  // Debug print
        self.id = id
        self.artist = artist
        self.title = title
        self.artworkUrl = nil
        self.tracks = []
    }
}

class AlbumDetailViewModel: ObservableObject {
    @Published var album: Album
    @Published var artwork: UIImage?
    private let discogsService = DiscogsService()
    private let logger = Logger(subsystem: "com.vinyls.app", category: "AlbumDetail")
    
    init(album: Album) {
        print("AlbumDetailViewModel init with: \(album.artist) - \(album.title)")  // Debug print
        self.album = album
        logger.debug("Initialized AlbumDetailViewModel for album: \(album.artist) - \(album.title)")
    }
    
    func refreshDiscogsData() async {
        print("refreshDiscogsData called for: \(album.artist) - \(album.title)")  // Debug print
        logger.debug("Starting Discogs data refresh for: \(album.artist) - \(album.title)")
        
        let (artworkUrl, tracks) = await discogsService.fetchAlbumDetails(
            artist: album.artist,
            title: album.title
        )
        
        print("Discogs API returned: artworkUrl=\(artworkUrl?.absoluteString ?? "none"), tracks=\(tracks.count)")  // Debug print
        logger.debug("Received response - Artwork URL: \(artworkUrl?.absoluteString ?? "none"), Tracks: \(tracks.count)")
        
        await MainActor.run {
            if let url = artworkUrl {
                album.artworkUrl = url
                Task {
                    do {
                        print("Loading artwork from: \(url.absoluteString)")  // Debug print
                        logger.debug("Loading artwork from URL: \(url.absoluteString)")
                        let imageData = try await discogsService.loadArtwork(for: url)
                        await MainActor.run {
                            artwork = UIImage(data: imageData)
                            print("Artwork loaded successfully")  // Debug print
                            logger.debug("Successfully loaded artwork")
                        }
                    } catch {
                        print("Failed to load artwork: \(error)")  // Debug print
                        logger.error("Failed to load artwork: \(error.localizedDescription)")
                    }
                }
            }
            
            album.tracks = tracks
            print("Updated album with \(tracks.count) tracks")  // Debug print
            logger.debug("Updated album with \(tracks.count) tracks")
        }
    }
}

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel
    private let logger = Logger(subsystem: "com.vinyls.app", category: "AlbumDetailView")
    
    init(album: Album) {
        print("AlbumDetailView init with: \(album.artist) - \(album.title)")  // Debug print
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(album: album))
        logger.debug("Initialized AlbumDetailView for album: \(album.artist) - \(album.title)")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let artwork = viewModel.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(8)
                        .shadow(radius: 5)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.album.artist)
                        .font(.title)
                        .bold()
                    Text(viewModel.album.title)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                if !viewModel.album.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tracks")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(viewModel.album.tracks, id: \.position) { track in
                            HStack {
                                Text(track.position)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .leading)
                                Text(track.title)
                                Spacer()
                                if !track.duration.isEmpty {
                                    Text(track.duration)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                            
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationBarItems(trailing: Button(action: {
            print("Refresh button tapped")  // Debug print
            logger.debug("Refresh button tapped")
            Task {
                await viewModel.refreshDiscogsData()
            }
        }) {
            Image(systemName: "arrow.clockwise")
        })
        .task {
            print("AlbumDetailView appeared, starting Discogs fetch")  // Debug print
            logger.debug("View appeared, starting initial Discogs data fetch")
            await viewModel.refreshDiscogsData()
        }
    }
} 