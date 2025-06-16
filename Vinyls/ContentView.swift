//
//  ContentView.swift
//  Vinyls
//

import SwiftUI
import CoreData

// @_exported import struct DiscogsClient.DiscogsTrack
// @_exported import class DiscogsService.DiscogsService

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var googleSheetsService = GoogleSheetsService()
    @State private var showingAddRecordSheet = false
    @State private var showingImportCSVSheet = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingExportSuccess = false
    @State private var searchText = ""
    @State private var sortOption = SortOption.artistAsc
    @State private var viewMode = ViewMode.grid
    
    enum ViewMode {
        case list
        case grid
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case artistAsc = "Artist (A-Z)"
        case artistDesc = "Artist (Z-A)"
        case albumAsc = "Album (A-Z)"
        case albumDesc = "Album (Z-A)"
        case yearAsc = "Year (Oldest First)"
        case yearDesc = "Year (Newest First)"
        
        var id: String { self.rawValue }
    }
    
    var sortDescriptors: [SortDescriptor<Item>] {
        switch sortOption {
        case .artistAsc:
            return [SortDescriptor(\Item.artist, order: .forward)]
        case .artistDesc:
            return [SortDescriptor(\Item.artist, order: .reverse)]
        case .albumAsc:
            return [SortDescriptor(\Item.albumTitle, order: .forward)]
        case .albumDesc:
            return [SortDescriptor(\Item.albumTitle, order: .reverse)]
        case .yearAsc:
            return [SortDescriptor(\Item.releaseYear, order: .forward)]
        case .yearDesc:
            return [SortDescriptor(\Item.releaseYear, order: .reverse)]
        }
    }
    
    var searchPredicate: NSPredicate? {
        if searchText.isEmpty {
            return nil
        }
        return NSPredicate(format: "albumTitle CONTAINS[cd] %@ OR artist CONTAINS[cd] %@ OR genre CONTAINS[cd] %@", 
                          searchText, searchText, searchText)
    }

    @FetchRequest private var items: FetchedResults<Item>
    
    init() {
        _items = FetchRequest<Item>(
            sortDescriptors: [SortDescriptor(\Item.artist, order: .forward)],
            animation: .default
        )
    }
    
    private func updateFetchRequest() {
        items.nsPredicate = searchPredicate
        items.sortDescriptors = sortDescriptors
    }

    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search", text: $searchText)
                        .onChange(of: searchText) { oldValue, newValue in
                            updateFetchRequest()
                        }
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            updateFetchRequest()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Sort and View Mode Controls
                HStack {
                    Picker("Sort by", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: sortOption) { oldValue, newValue in
                        updateFetchRequest()
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewMode = viewMode == .list ? .grid : .list
                    }) {
                        Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                            .imageScale(.large)
                    }
                }
                .padding(.horizontal)
                
                // Records view
                Group {
                    if viewMode == .list {
                        List {
                            ForEach(items) { item in
                                NavigationLink {
                                    RecordDetailView(item: item)
                                } label: {
                                    RecordRowView(item: item)
                                }
                            }
                            .onDelete(perform: deleteItems)
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                            ], spacing: 16) {
                                ForEach(items) { item in
                                    RecordGridItemView(item: item)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: { showingAddRecordSheet = true }) {
                        Label("Add Record", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: { showingImportCSVSheet = true }) {
                            Label("Import CSV", systemImage: "square.and.arrow.down")
                        }
                        Button(action: exportToGoogleSheets) {
                            Label("Export to Google Sheets", systemImage: "arrow.up.doc")
                        }
                        Button(role: .destructive, action: { showingDeleteAllConfirmation = true }) {
                            Label("Delete All Records", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .navigationTitle("Vinyl Collection")
            
            Text("Select a record to view details")
        }
        .sheet(isPresented: $showingAddRecordSheet) {
            AddRecordView(isPresented: $showingAddRecordSheet)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingImportCSVSheet) {
            ImportCSVView()
                .environment(\.managedObjectContext, viewContext)
        }
        .alert("Delete All Records?", isPresented: $showingDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllItems()
            }
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete all records in your collection?")
        }
        .alert("Export Successful", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your vinyl collection has been exported to Google Sheets.")
        }
        .onAppear {
            updateFetchRequest()
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteAllItems() {
        withAnimation {
            items.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func exportToGoogleSheets() {
        let albums = items.map { item in
            Album(
                title: item.albumTitle ?? "",
                artist: item.artist ?? "",
                year: Int(item.releaseYear),
                genre: item.genre ?? "",
                notes: item.notes ?? ""
            )
        }
        
        googleSheetsService.exportToGoogleSheets(albums: albums)
    }
}

struct RecordDetailView: View {
    let item: Item
    @StateObject private var discogsService = DiscogsService.shared
    @State private var tracks: [DiscogsTrack] = []
    @State private var currentArtworkURL: String = ""
    @State private var isEditing = false
    
    // Editable states
    @State private var editedArtist: String = ""
    @State private var editedAlbumTitle: String = ""
    @State private var editedYear: String = ""
    @State private var editedGenre: String = ""
    @State private var editedNotes: String = ""
    
    init(item: Item) {
        print("🎵 RecordDetailView init called for: \(item.artist ?? "") - \(item.albumTitle ?? "")")
        self.item = item
        _currentArtworkURL = State(initialValue: item.coverArtURL ?? "")
        _editedArtist = State(initialValue: item.artist ?? "")
        _editedAlbumTitle = State(initialValue: item.albumTitle ?? "")
        _editedYear = State(initialValue: item.releaseYear > 0 ? "\(item.releaseYear)" : "")
        _editedGenre = State(initialValue: item.genre ?? "")
        _editedNotes = State(initialValue: item.notes ?? "")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                if currentArtworkURL != "" {
                    AsyncImage(url: URL(string: currentArtworkURL)) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 300)
                    .cornerRadius(8)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 120))
                        .frame(height: 300)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("Artist")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        if isEditing {
                            TextField("Artist", text: $editedArtist)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(item.artist ?? "Unknown")
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Text("Album")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        if isEditing {
                            TextField("Album Title", text: $editedAlbumTitle)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(item.albumTitle ?? "Unknown")
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Text("Year")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        if isEditing {
                            TextField("Year", text: $editedYear)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        } else {
                            Text(item.releaseYear > 0 ? "\(item.releaseYear)" : "Unknown")
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Text("Genre")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        if isEditing {
                            TextField("Genre", text: $editedGenre)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(item.genre ?? "Unknown")
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Text("Notes")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        if isEditing {
                            TextField("Notes", text: $editedNotes)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(item.notes ?? "None")
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Text("Identifier")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        Text(item.identifier ?? "None")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if !tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tracks")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(tracks, id: \.position) { track in
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
            .padding()
        }
        .navigationTitle(item.albumTitle ?? "Record Details")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: {
                        print("🔄 Refresh button tapped")
                        Task {
                            await refreshDiscogsData(forceRefresh: true)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                            isEditing = false
                        }
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
        }
        .task {
            print("👁️ RecordDetailView appeared, checking if Discogs data needed")
            await refreshDiscogsData(forceRefresh: false)
        }
    }
    
    private func saveChanges() {
        if let context = item.managedObjectContext {
            context.perform {
                item.artist = editedArtist.isEmpty ? nil : editedArtist
                item.albumTitle = editedAlbumTitle.isEmpty ? nil : editedAlbumTitle
                item.genre = editedGenre.isEmpty ? nil : editedGenre
                item.notes = editedNotes.isEmpty ? nil : editedNotes
                
                if let year = Int16(editedYear), year > 0 {
                    item.releaseYear = year
                } else {
                    item.releaseYear = 0
                }
                
                try? context.save()
            }
        }
    }
    
    private func refreshDiscogsData(forceRefresh: Bool) async {
        guard let artist = item.artist, let title = item.albumTitle else { return }
        
        // Check for complete local data first
        if !forceRefresh {
            let hasStoredArtwork = item.coverArtURL != nil && !item.coverArtURL!.isEmpty
            let hasStoredTracks = item.tracklist != nil && 
                (try? JSONDecoder().decode([DiscogsTrack].self, from: item.tracklist!)) != nil
            
            if hasStoredArtwork && hasStoredTracks {
                print("📦 Using stored local data for: \(artist) - \(title)")
                currentArtworkURL = item.coverArtURL!
                tracks = try! JSONDecoder().decode([DiscogsTrack].self, from: item.tracklist!)
                return
            }
        }
        
        // If we get here, we need to fetch from Discogs
        print("🔍 Fetching Discogs data for: \(artist) - \(title)")
        let (artworkUrl, fetchedTracks, genre, year, notes) = await discogsService.fetchAlbumDetails(
            artist: artist,
            title: title
        )
        
        print("📥 Got Discogs data - artwork: \(artworkUrl?.absoluteString ?? "none"), tracks: \(fetchedTracks.count)")
        
        // Update the tracks if we got any
        if !fetchedTracks.isEmpty {
            tracks = fetchedTracks
            
            // Store tracks in Core Data
            if let context = item.managedObjectContext {
                await context.perform {
                    do {
                        let tracksData = try JSONEncoder().encode(fetchedTracks)
                        item.tracklist = tracksData
                        
                        // Update other fields if they're empty/default
                        if item.genre == nil || item.genre == "Unknown" {
                            item.genre = genre
                        }
                        if item.releaseYear == 0, let yearStr = year, let yearInt = Int16(yearStr) {
                            item.releaseYear = yearInt
                        }
                        if item.notes == nil {
                            item.notes = notes
                        }
                        
                        try? context.save()
                        print("💾 Updated tracks data and additional fields in Core Data")
                    } catch {
                        print("❌ Failed to encode tracks data: \(error)")
                    }
                }
            }
        }
        
        // Update artwork URL if we got one from Discogs
        if let artworkUrl = artworkUrl {
            // Update both the local state and Core Data
            currentArtworkURL = artworkUrl.absoluteString
            
            if let context = item.managedObjectContext {
                await context.perform {
                    item.coverArtURL = artworkUrl.absoluteString
                    try? context.save()
                    print("💾 Updated cover art URL in Core Data")
                }
            }
        }
    }
}

struct AddRecordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var isPresented: Bool
    @StateObject private var discogsService = DiscogsService.shared
    
    @State private var showingBarcodeScanner = false
    @State private var isManualEntry = false
    @State private var scannedBarcodes: [String] = []
    @State private var barcodeResults: [String: (
        coverUrl: URL?,
        artist: String?,
        title: String?,
        genre: String?,
        year: String?,
        tracklist: [DiscogsTrack]?,
        notes: String?
    )] = [:]
    
    // Manual entry states
    @State private var manualArtist = ""
    @State private var manualTitle = ""
    @State private var manualGenre = ""
    @State private var manualYear = ""
    @State private var manualNotes = ""
    @State private var manualIdentifier = ""
    
    var hasValidRecordsToSave: Bool {
        if isManualEntry {
            return !manualArtist.isEmpty && !manualTitle.isEmpty
        } else {
            return !scannedBarcodes.isEmpty && scannedBarcodes.allSatisfy { barcode in
                if let result = barcodeResults[barcode] {
                    return result.artist != nil && result.title != nil
                }
                return false
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Entry Method")) {
                    Picker("Entry Method", selection: $isManualEntry) {
                        Text("Barcode Scan").tag(false)
                        Text("Manual Entry").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                if isManualEntry {
                    manualEntrySection
                } else {
                    scanSection
                    scannedResultsSection
                }
            }
            .navigationTitle("Add New Vinyl")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        addRecords()
                        isPresented = false
                    }
                    .disabled(!hasValidRecordsToSave)
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView(scannedBarcodes: $scannedBarcodes)
            }
            .onChange(of: scannedBarcodes) { oldValue, newValue in
                // Find newly added barcodes
                let newBarcodes = Set(newValue).subtracting(Set(oldValue))
                for barcode in newBarcodes {
                    // Start background search for each new barcode
                    discogsService.startBackgroundSearch(for: barcode) { coverUrl, artist, title, genre, year, tracklist, notes in
                        barcodeResults[barcode] = (
                            coverUrl: coverUrl,
                            artist: artist,
                            title: title,
                            genre: genre,
                            year: year,
                            tracklist: tracklist,
                            notes: notes
                        )
                    }
                }
                
                // Find removed barcodes
                let removedBarcodes = Set(oldValue).subtracting(Set(newValue))
                for barcode in removedBarcodes {
                    discogsService.cancelSearch(for: barcode)
                    barcodeResults.removeValue(forKey: barcode)
                }
            }
        }
    }
    
    private var manualEntrySection: some View {
        Section(header: Text("Album Information")) {
            TextField("Artist", text: $manualArtist)
            TextField("Album Title", text: $manualTitle)
            TextField("Genre (optional)", text: $manualGenre)
            TextField("Year (optional)", text: $manualYear)
                .keyboardType(.numberPad)
                .onChange(of: manualYear) { oldValue, newValue in
                    if !newValue.isEmpty && Int(newValue) == nil {
                        manualYear = oldValue
                    }
                }
            TextField("Notes (optional)", text: $manualNotes)
            TextField("Identifier (optional)", text: $manualIdentifier)
        }
    }
    
    private var scanSection: some View {
        Section(header: Text("Scan")) {
            Button(action: {
                showingBarcodeScanner = true
            }) {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                    Text("Scan Barcode")
                }
            }
        }
    }
    
    private var scannedResultsSection: some View {
        Section(header: Text("Scanned Items")) {
            if scannedBarcodes.isEmpty {
                Text("No barcodes scanned yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(scannedBarcodes, id: \.self) { barcode in
                    BarcodeResultRow(
                        barcode: barcode,
                        result: barcodeResults[barcode],
                        onRemove: {
                            if let index = scannedBarcodes.firstIndex(of: barcode) {
                                scannedBarcodes.remove(at: index)
                            }
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private func addRecords() {
        withAnimation {
            if isManualEntry {
                // Add single manual record
                let newItem = Item(context: viewContext)
                newItem.timestamp = Date()
                newItem.artist = manualArtist
                newItem.albumTitle = manualTitle
                newItem.genre = manualGenre.isEmpty ? nil : manualGenre
                newItem.notes = manualNotes.isEmpty ? nil : manualNotes
                newItem.identifier = manualIdentifier.isEmpty ? nil : manualIdentifier
                
                if let year = Int16(manualYear), year > 0 {
                    newItem.releaseYear = year
                } else {
                    newItem.releaseYear = 0
                }
            } else {
                // Add scanned records
                for barcode in scannedBarcodes {
                    guard let result = barcodeResults[barcode],
                          let artist = result.artist,
                          let title = result.title else {
                        continue
                    }
                    
                    let newItem = Item(context: viewContext)
                    newItem.timestamp = Date()
                    newItem.artist = artist
                    newItem.albumTitle = title
                    newItem.genre = result.genre
                    newItem.notes = result.notes
                    newItem.identifier = barcode
                    
                    if let yearStr = result.year, let year = Int16(yearStr) {
                        newItem.releaseYear = year
                    } else {
                        newItem.releaseYear = 0
                    }
                    
                    if let coverUrl = result.coverUrl {
                        newItem.coverArtURL = coverUrl.absoluteString
                    }
                    
                    // Save tracklist if available
                    if let tracklist = result.tracklist {
                        do {
                            let tracklistData = try JSONEncoder().encode(tracklist)
                            newItem.tracklist = tracklistData
                        } catch {
                            print("Failed to encode tracklist: \(error)")
                        }
                    }
                }
            }

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct BarcodeResultRow: View {
    let barcode: String
    let result: (
        coverUrl: URL?,
        artist: String?,
        title: String?,
        genre: String?,
        year: String?,
        tracklist: [DiscogsTrack]?,
        notes: String?
    )?
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Album info section - wrapped in a non-interactive container
            HStack {
                if let result = result {
                    if result.artist == nil && result.title == nil {
                        // No results found
                        Image(systemName: "magnifyingglass")
                            .frame(width: 50, height: 50)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                        
                        VStack(alignment: .leading) {
                            Text("No match found")
                                .font(.subheadline)
                            Text(barcode)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Show album details if available
                        if let coverUrl = result.coverUrl {
                            AsyncImage(url: coverUrl) { image in
                                image.resizable()
                            } placeholder: {
                                Color.gray
                            }
                            .frame(width: 50, height: 50)
                            .cornerRadius(4)
                        } else {
                            Image(systemName: "music.note")
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        VStack(alignment: .leading) {
                            if let artist = result.artist {
                                Text(artist)
                                    .font(.headline)
                            }
                            if let title = result.title {
                                Text(title)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if let year = result.year {
                                Text(year)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    // Show loading state
                    ProgressView()
                        .frame(width: 50)
                    
                    VStack(alignment: .leading) {
                        Text("Searching Discogs...")
                            .font(.subheadline)
                        Text(barcode)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color(UIColor.systemBackground))
            .allowsHitTesting(false)
            
            // Delete button in its own container
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .padding(12)
            }
        }
        .background(Color(UIColor.systemBackground))
    }
}

// Extract record row view into a separate component
struct RecordRowView: View {
    @ObservedObject var item: Item
    
    var body: some View {
        HStack {
            if item.coverArtURL == nil {
                Image(systemName: "music.note")
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                    .overlay {
                        if item.coverArtURL == "" {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                    }
            } else if item.coverArtURL == "" {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 50, height: 50)
            } else {
                AsyncImage(url: URL(string: item.coverArtURL ?? "")) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 50, height: 50)
                .cornerRadius(4)
            }
            
            VStack(alignment: .leading) {
                Text(item.artist ?? "Unknown Artist")
                    .font(.headline)
                Text(item.albumTitle ?? "Unknown Album")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// Update grid item view component with overlay
struct RecordGridItemView: View {
    @ObservedObject var item: Item
    
    var body: some View {
        NavigationLink {
            RecordDetailView(item: item)
        } label: {
            VStack {
                ZStack(alignment: .bottom) {
                    if item.coverArtURL == nil {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .background(Color.gray.opacity(0.2))
                            .overlay {
                                if item.coverArtURL == "" {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                            }
                    } else if item.coverArtURL == "" {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .background(Color.gray.opacity(0.2))
                    } else {
                        AsyncImage(url: URL(string: item.coverArtURL ?? "")) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray
                        }
                        .aspectRatio(1, contentMode: .fill)
                    }
                    
                    // Text overlay with gradient background
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.artist ?? "Unknown Artist")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(item.albumTitle ?? "Unknown Album")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.7),
                                Color.black.opacity(0.3)
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .foregroundColor(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Add this struct to match the GoogleSheetsService expectations
struct Album {
    let title: String
    let artist: String
    let year: Int
    let genre: String
    let notes: String
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
