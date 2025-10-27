//
//  ContentView.swift
//  Vinyls
//

import SwiftUI
import PhotosUI
import Photos
import UIKit
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
    @StateObject private var importManager = BackgroundImportManager.shared
    
    enum ViewMode {
        case list
        case grid
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case artistAsc = "Artist (A-Z)"
        case artistDesc = "Artist (Z-A)"
        case albumAsc = "Album (A-Z)"
        case albumDesc = "Album (Z-A)"
        case yearAsc = "Year (Oldest)"
        case yearDesc = "Year (Newest)"
        case dateAddedDesc = "Date Added (Newest)"
        case dateAddedAsc = "Date Added (Oldest)"
        
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
        case .dateAddedDesc:
            return [SortDescriptor(\Item.timestamp, order: .reverse)]
        case .dateAddedAsc:
            return [SortDescriptor(\Item.timestamp, order: .forward)]
        }
    }

    // Whether current sort is alphabetical (artist or album)
    var isAlphaSort: Bool {
        switch sortOption {
        case .artistAsc, .artistDesc, .albumAsc, .albumDesc:
            return true
        default:
            return false
        }
    }

    // Credential availability checks
    private var isDiscogsConfigured: Bool {
        !API.discogsToken.isEmpty
    }

    // Determine section key (first letter) based on current alpha sort key
    private func sectionKeyForItem(_ item: Item) -> String {
        let raw: String = {
            switch sortOption {
            case .artistAsc, .artistDesc:
                return item.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            case .albumAsc, .albumDesc:
                return item.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            default:
                return item.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }()
        guard !raw.isEmpty else { return "#" }
        let scalars = raw.unicodeScalars
        guard let first = scalars.first else { return "#" }
        if CharacterSet.letters.contains(first) {
            return String(raw.prefix(1)).uppercased()
        }
        return "#"
    }

    // Build ordered sections from fetched items, preserving overall sort order
    private var sectionedItems: [(key: String, items: [Item])] {
        var sections: [(String, [Item])] = []
        var currentKey: String? = nil
        var currentItems: [Item] = []
        for item in items {
            let key = sectionKeyForItem(item)
            if currentKey == nil {
                currentKey = key
                currentItems = [item]
            } else if key == currentKey {
                currentItems.append(item)
            } else {
                sections.append((currentKey!, currentItems))
                currentKey = key
                currentItems = [item]
            }
        }
        if let currentKey = currentKey {
            sections.append((currentKey, currentItems))
        }
        return sections
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

    // MARK: - Extracted content to reduce type-checking complexity
    private var recordsContent: some View {
        Group {
            if viewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
    }

    private var listContent: some View {
        Group {
            if isAlphaSort {
                listAlphaContent
            } else {
                listSimpleContent
            }
        }
    }

    private var gridContent: some View {
        Group {
            if isAlphaSort {
                gridAlphaContent
            } else {
                gridSimpleContent
            }
        }
    }

    private var listAlphaContent: some View {
        List {
            ForEach(sectionedItems, id: \.key) { section in
                Section(header: Text(section.key)) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            RecordDetailView(item: item)
                        } label: {
                            RecordRowView(item: item)
                        }
                    }
                    .onDelete { offsets in
                        deleteItems(offsets: offsets, in: section.items)
                    }
                }
            }
        }
    }

    private var listSimpleContent: some View {
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
    }

    private var gridAlphaContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sectionedItems, id: \.key) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.key)
                            .font(.headline)
                            .padding(.leading, 4)
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                        ], spacing: 16) {
                            ForEach(section.items) { item in
                                RecordGridItemView(item: item)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var gridSimpleContent: some View {
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

    var body: some View {
        NavigationView {
            VStack {
                if importManager.isImporting {
                    HStack(spacing: 12) {
                        ProgressView(value: importManager.progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: .infinity)
                        Text("\(importManager.completed)/\(importManager.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                }
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
                
                if !isDiscogsConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Discogs lookups disabled: missing API token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 2)
                }
                recordsContent
            }
            .toolbar {
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
            AddRecordView(isPresented: $showingAddRecordSheet, onDidAdd: { _ in
                // After adding, switch to "Date Added (Newest)" so new items are visible at the top
                sortOption = .dateAddedDesc
            })
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

	private func deleteItems(offsets: IndexSet, in sectionItems: [Item]) {
		withAnimation {
			offsets.map { sectionItems[$0] }.forEach(viewContext.delete)

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
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @Namespace private var artworkNamespace
    @State private var isZoomedArtwork = false
    @State private var zoomDragOffset: CGSize = .zero
    @State private var isShowingPhotoPickerSheet = false
    @State private var isShowingSaveDialog = false
    @State private var isSavingToPhotos = false
    @State private var isEditing = false
    @State private var isEditingNotesOnly = false
    @State private var isEditingArtistOnly = false
    @State private var isEditingAlbumOnly = false
    @State private var isEditingYearOnly = false
    @State private var isEditingGenreOnly = false
    @FocusState private var isNotesFieldFocused: Bool
    @FocusState private var isArtistFieldFocused: Bool
    @FocusState private var isAlbumFieldFocused: Bool
    @FocusState private var isYearFieldFocused: Bool
    @FocusState private var isGenreFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    
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
    
    private var artworkMatchedId: String {
        "artwork-\(item.objectID.uriRepresentation().absoluteString)"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                if isEditing {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Album")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal)
                }
                
                AlbumArtworkView(urlString: currentArtworkURL)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 300)
                    .cornerRadius(8)
                    .matchedGeometryEffect(id: artworkMatchedId, in: artworkNamespace)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            isZoomedArtwork = true
                        }
                    }
                    .onLongPressGesture {
                        // Long-press shortcut to replace artwork
                        isShowingPhotoPickerSheet = true
                    }

                if isEditing {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, preferredItemEncoding: .automatic) {
                        HStack {
                            Image(systemName: "photo")
                            Text("Replace Artwork")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
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
                            if isEditingArtistOnly {
                                HStack(spacing: 8) {
                                    TextField("Artist", text: $editedArtist)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .focused($isArtistFieldFocused)
                                        .onSubmit { saveArtistOnly() }
                                    Button { saveArtistOnly() } label: { Image(systemName: "checkmark.circle.fill") }
                                        .buttonStyle(.plain)
                                    Button {
                                        editedArtist = item.artist ?? ""
                                        isEditingArtistOnly = false
                                    } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain)
                                }
                                .onAppear { isArtistFieldFocused = true }
                            } else {
                                Text(item.artist ?? "Unknown")
                                    .onLongPressGesture {
                                        editedArtist = item.artist ?? ""
                                        isEditingArtistOnly = true
                                    }
                            }
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
                            if isEditingAlbumOnly {
                                HStack(spacing: 8) {
                                    TextField("Album Title", text: $editedAlbumTitle)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .focused($isAlbumFieldFocused)
                                        .onSubmit { saveAlbumOnly() }
                                    Button { saveAlbumOnly() } label: { Image(systemName: "checkmark.circle.fill") }
                                        .buttonStyle(.plain)
                                    Button {
                                        editedAlbumTitle = item.albumTitle ?? ""
                                        isEditingAlbumOnly = false
                                    } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain)
                                }
                                .onAppear { isAlbumFieldFocused = true }
                            } else {
                                Text(item.albumTitle ?? "Unknown")
                                    .onLongPressGesture {
                                        editedAlbumTitle = item.albumTitle ?? ""
                                        isEditingAlbumOnly = true
                                    }
                            }
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
                            if isEditingYearOnly {
                                HStack(spacing: 8) {
                                    TextField("Year", text: $editedYear)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .keyboardType(.numberPad)
                                        .focused($isYearFieldFocused)
                                        .onSubmit { saveYearOnly() }
                                    Button { saveYearOnly() } label: { Image(systemName: "checkmark.circle.fill") }
                                        .buttonStyle(.plain)
                                    Button {
                                        editedYear = item.releaseYear > 0 ? String(item.releaseYear) : ""
                                        isEditingYearOnly = false
                                    } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain)
                                }
                                .onAppear { isYearFieldFocused = true }
                            } else {
                                Text(item.releaseYear > 0 ? String(item.releaseYear) : "Unknown")
                                    .onLongPressGesture {
                                        editedYear = item.releaseYear > 0 ? String(item.releaseYear) : ""
                                        isEditingYearOnly = true
                                    }
                            }
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
                            if isEditingGenreOnly {
                                HStack(spacing: 8) {
                                    TextField("Genre", text: $editedGenre)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .focused($isGenreFieldFocused)
                                        .onSubmit { saveGenreOnly() }
                                    Button { saveGenreOnly() } label: { Image(systemName: "checkmark.circle.fill") }
                                        .buttonStyle(.plain)
                                    Button {
                                        editedGenre = item.genre ?? ""
                                        isEditingGenreOnly = false
                                    } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain)
                                }
                                .onAppear { isGenreFieldFocused = true }
                            } else {
                                Text(item.genre ?? "Unknown")
                                    .onLongPressGesture {
                                        editedGenre = item.genre ?? ""
                                        isEditingGenreOnly = true
                                    }
                            }
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Text("Notes")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        if isEditing {
                            TextEditor(text: $editedNotes)
                                .frame(minHeight: 100)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        } else {
                            if isEditingNotesOnly {
                                HStack(spacing: 8) {
                                    TextEditor(text: $editedNotes)
                                        .frame(minHeight: 100)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                        .focused($isNotesFieldFocused)
                                        .onSubmit { saveNotesOnly() }
                                    Button {
                                        saveNotesOnly()
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        editedNotes = item.notes ?? ""
                                        isEditingNotesOnly = false
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onAppear { isNotesFieldFocused = true }
                            } else {
                                Text(item.notes ?? "None")
                                    .onLongPressGesture {
                                        editedNotes = item.notes ?? ""
                                        isEditingNotesOnly = true
                                    }
                            }
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
        .alert("Delete Album?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete this album?")
        }
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                isEditingNotesOnly = false
                isEditingArtistOnly = false
                isEditingAlbumOnly = false
                isEditingYearOnly = false
                isEditingGenreOnly = false
            }
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task { await handleSelectedPhoto(newValue) }
        }
        .overlay(alignment: .center) {
            if isZoomedArtwork {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                isZoomedArtwork = false
                                zoomDragOffset = .zero
                            }
                        }
                    GeometryReader { proxy in
                        AlbumArtworkView(urlString: currentArtworkURL)
                            .matchedGeometryEffect(id: artworkMatchedId, in: artworkNamespace)
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                            .offset(zoomDragOffset)
                            .scaleEffect(zoomScaleFor(offset: zoomDragOffset))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        zoomDragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        let vertical = value.translation.height
                                        let threshold: CGFloat = 140
                                        if abs(vertical) > threshold {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                                isZoomedArtwork = false
                                                zoomDragOffset = .zero
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                                zoomDragOffset = .zero
                                            }
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    isShowingSaveDialog = true
                                }
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    isZoomedArtwork = false
                                    zoomDragOffset = .zero
                                }
                            }
                    }
                    .ignoresSafeArea()
                }
                .transition(.opacity)
            }
        }
        .confirmationDialog("Artwork", isPresented: $isShowingSaveDialog) {
            Button("Save Image to Photos") {
                Task { await saveZoomedImageToPhotos() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isShowingPhotoPickerSheet) {
            PhotoPickerView { image in
                Task {
                    if let image = image, let data = image.jpegData(compressionQuality: 0.9) {
                        do {
                            let fileURL = try saveArtworkData(data)
                            await updateCoverArt(with: fileURL)
                        } catch {
                            print("❌ Failed to save picked image: \(error)")
                        }
                    }
                    isShowingPhotoPickerSheet = false
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

    private func saveNotesOnly() {
        if let context = item.managedObjectContext {
            context.perform {
                item.notes = editedNotes.isEmpty ? nil : editedNotes
                try? context.save()
                DispatchQueue.main.async {
                    isEditingNotesOnly = false
                }
            }
        } else {
            isEditingNotesOnly = false
        }
    }

    private func saveArtistOnly() {
        if let context = item.managedObjectContext {
            context.perform {
                item.artist = editedArtist.isEmpty ? nil : editedArtist
                try? context.save()
                DispatchQueue.main.async {
                    isEditingArtistOnly = false
                }
            }
        } else {
            isEditingArtistOnly = false
        }
    }

    private func saveAlbumOnly() {
        if let context = item.managedObjectContext {
            context.perform {
                item.albumTitle = editedAlbumTitle.isEmpty ? nil : editedAlbumTitle
                try? context.save()
                DispatchQueue.main.async {
                    isEditingAlbumOnly = false
                }
            }
        } else {
            isEditingAlbumOnly = false
        }
    }

    private func saveYearOnly() {
        if let context = item.managedObjectContext {
            context.perform {
                if let year = Int16(editedYear), year > 0 {
                    item.releaseYear = year
                } else {
                    item.releaseYear = 0
                }
                try? context.save()
                DispatchQueue.main.async {
                    isEditingYearOnly = false
                }
            }
        } else {
            isEditingYearOnly = false
        }
    }

    private func saveGenreOnly() {
        if let context = item.managedObjectContext {
            context.perform {
                item.genre = editedGenre.isEmpty ? nil : editedGenre
                try? context.save()
                DispatchQueue.main.async {
                    isEditingGenreOnly = false
                }
            }
        } else {
            isEditingGenreOnly = false
        }
    }
    
    private func deleteItem() {
        if let context = item.managedObjectContext {
            context.perform {
                context.delete(item)
                try? context.save()
                DispatchQueue.main.async {
                    dismiss()
                }
            }
        } else {
            dismiss()
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
                if let data = item.tracklist, let decoded = try? JSONDecoder().decode([DiscogsTrack].self, from: data) {
                    tracks = decoded
                } else {
                    tracks = []
                }
                return
            }
        }
        
        // If we get here, we need to fetch from Discogs
        print("🔍 Fetching Discogs data for: \(artist) - \(title)")
        let (artworkUrl, fetchedTracks, genre, year, _) = await discogsService.fetchAlbumDetails(
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
                        // Intentionally do not set notes from Discogs; leave for user to add
                        
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

    private func handleSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                if let image = UIImage(data: data), let jpegData = image.jpegData(compressionQuality: 0.9) {
                    let fileURL = try saveArtworkData(jpegData)
                    await updateCoverArt(with: fileURL)
                } else {
                    // Fallback: write original data if convertible failed
                    let fileURL = try saveArtworkData(data)
                    await updateCoverArt(with: fileURL)
                }
            }
        } catch {
            print("❌ Failed to load selected photo: \(error)")
        }
    }

    private func saveArtworkData(_ data: Data) throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let artworkDir = documentsURL.appendingPathComponent("Artwork", isDirectory: true)
        if !fileManager.fileExists(atPath: artworkDir.path) {
            try fileManager.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        }
        let filename = UUID().uuidString + ".jpg"
        let destination = artworkDir.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func updateCoverArt(with fileURL: URL) async {
        guard let context = item.managedObjectContext else { return }
        await context.perform {
            let fileManager = FileManager.default
            if let existing = item.coverArtURL, let existingURL = URL(string: existing), existingURL.isFileURL {
                try? fileManager.removeItem(at: existingURL)
            }
            item.coverArtURL = fileURL.absoluteString
            try? context.save()
            DispatchQueue.main.async {
                currentArtworkURL = fileURL.absoluteString
            }
        }
    }
    
    private func zoomScaleFor(offset: CGSize) -> CGFloat {
        let distance = sqrt(offset.width * offset.width + offset.height * offset.height)
        let maxDistance: CGFloat = 300
        let clamped = min(distance, maxDistance)
        return 1.0 - (clamped / (maxDistance * 5))
    }

    private func saveZoomedImageToPhotos() async {
        guard !isSavingToPhotos else { return }
        isSavingToPhotos = true
        defer { isSavingToPhotos = false }
        guard let url = URL(string: currentArtworkURL) else { return }
        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (fetched, _) = try await URLSession.shared.data(from: url)
                data = fetched
            }
            guard let image = UIImage(data: data) else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        } catch {
            print("❌ Failed to save image to Photos: \(error)")
        }
    }
}

struct AddRecordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var isPresented: Bool
    @StateObject private var discogsService = DiscogsService.shared
    let onDidAdd: ([Item]) -> Void
    
    @State private var showingBarcodeScanner = false
    @State private var isManualEntry = false
    @State private var useIdentifierLookup = true
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
    @State private var identifierPreview: IdentifierLookupData? = nil
    @State private var showingIdentifierPreview = false
    @State private var identifierNoResultAlert = false
    @State private var showDuplicateSummary = false
    @State private var duplicateSummaryMessage = ""

    // Discogs configured?
    private var isDiscogsConfigured: Bool { !API.discogsToken.isEmpty }
    
    var hasValidRecordsToSave: Bool {
        if isManualEntry {
            if useIdentifierLookup {
                return !manualIdentifier.isEmpty
            } else {
                return !manualArtist.isEmpty && !manualTitle.isEmpty
            }
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

                if !isDiscogsConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Discogs lookups disabled: missing API token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    Button(isManualEntry && useIdentifierLookup ? "Search" : "Save") {
                        Task { await addRecords() }
                    }
                    .disabled(!hasValidRecordsToSave || discogsService.isLoading)
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView(scannedBarcodes: $scannedBarcodes)
            }
            .sheet(isPresented: $showingIdentifierPreview) {
                if let preview = identifierPreview {
                    IdentifierLookupPreviewView(
                        preview: preview,
                        onConfirm: {
                            // Create and save the item, then dismiss both sheets
                            let newItem = Item(context: viewContext)
                            newItem.timestamp = Date()
                            newItem.identifier = manualIdentifier
                            newItem.artist = preview.artist ?? (manualArtist.isEmpty ? nil : manualArtist)
                            newItem.albumTitle = preview.title ?? (manualTitle.isEmpty ? nil : manualTitle)
                            newItem.genre = preview.genre ?? (manualGenre.isEmpty ? nil : manualGenre)
                            newItem.notes = manualNotes.isEmpty ? nil : manualNotes
                            if let yearStr = preview.year, let year = Int16(yearStr) {
                                newItem.releaseYear = year
                            } else if let year = Int16(manualYear), year > 0 {
                                newItem.releaseYear = year
                            } else {
                                newItem.releaseYear = 0
                            }
                            if let coverUrl = preview.coverUrl {
                                newItem.coverArtURL = coverUrl.absoluteString
                            }
                            if let tracklist = preview.tracklist {
                                do {
                                    let data = try JSONEncoder().encode(tracklist)
                                    newItem.tracklist = data
                                } catch {
                                    print("Failed to encode tracklist: \(error)")
                                }
                            }
                            do { try viewContext.save() } catch {
                                let nsError = error as NSError
                                print("Unresolved error \(nsError), \(nsError.userInfo)")
                            }
                            // Notify parent view so it can adjust sorting
                            onDidAdd([newItem])
                            showingIdentifierPreview = false
                            withAnimation { isPresented = false }
                        },
                        onCancel: {
                            showingIdentifierPreview = false
                        }
                    )
                }
            }
            .alert("No match found", isPresented: $identifierNoResultAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("We couldn't find an album for that identifier. You can try another identifier or switch to Manual Input.")
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
            .alert("Import Result", isPresented: $showDuplicateSummary) {
                Button("OK") {
                    isPresented = false
                }
            } message: {
                Text(duplicateSummaryMessage)
            }
        }
    }
    
    private var manualEntrySection: some View {
        Section(header: Text("Manual Entry")) {
            Picker("Method", selection: $useIdentifierLookup) {
                Text("Search Identifier").tag(true)
                Text("Manual Input").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())

            if useIdentifierLookup {
                TextField("Identifier (e.g. B0032752-01)", text: $manualIdentifier)
                    .submitLabel(.search)
                    .onSubmit {
                        if useIdentifierLookup && !manualIdentifier.isEmpty && !discogsService.isLoading {
                            Task { await addRecords() }
                        }
                    }
                if discogsService.isLoading {
                    ProgressView().progressViewStyle(.circular)
                }
            } else {
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
            }
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
    
    private func addRecords() async {
        var newlyAdded: [Item] = []
        if isManualEntry {
            if useIdentifierLookup, !manualIdentifier.isEmpty {
                // Lookup via Discogs using identifier and present preview instead of saving immediately
                let result = await discogsService.lookupByIdentifier(manualIdentifier)
                if result.artist == nil && result.title == nil {
                    identifierNoResultAlert = true
                } else {
                    identifierPreview = IdentifierLookupData(
                        coverUrl: result.coverUrl,
                        artist: result.artist,
                        title: result.title,
                        genre: result.genre,
                        year: result.year,
                        tracklist: result.tracklist,
                        notes: nil
                    )
                    showingIdentifierPreview = true
                }
            } else {
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
                newlyAdded.append(newItem)
            }
        } else {
            // Add scanned records
            var addedCount = 0
            var addedDisplays: [String] = []
            var skippedBarcodes: [String] = []
            var existingIdentifiers = Set<String>()
            var existingDisplayByIdentifier: [String: String] = [:]

            if !scannedBarcodes.isEmpty {
                let request: NSFetchRequest<Item> = Item.fetchRequest()
                request.predicate = NSPredicate(format: "identifier IN %@", scannedBarcodes)
                do {
                    let existingItems = try viewContext.fetch(request)
                    existingIdentifiers = Set(existingItems.compactMap { $0.identifier })
                    existingDisplayByIdentifier = Dictionary(uniqueKeysWithValues: existingItems.compactMap { item in
                        guard let id = item.identifier else { return nil }
                        let artist = (item.artist?.isEmpty == false) ? item.artist! : "Unknown Artist"
                        let title = (item.albumTitle?.isEmpty == false) ? item.albumTitle! : "Unknown Album"
                        return (id, "\(artist) - \(title)")
                    })
                } catch {
                    print("Failed to fetch existing identifiers: \(error)")
                    existingIdentifiers = []
                }
            }

            for barcode in scannedBarcodes {
                if existingIdentifiers.contains(barcode) {
                    let display = existingDisplayByIdentifier[barcode] ?? barcode
                    skippedBarcodes.append(display)
                    continue
                }

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

                addedCount += 1
                let display = "\(artist) - \(title)"
                addedDisplays.append(display)
                newlyAdded.append(newItem)
            }

            let skippedCount = skippedBarcodes.count
            let truncateTo = 32
            let addedList = addedDisplays.map { entry -> String in
                let singleLine = entry.replacingOccurrences(of: "\n", with: " ")
                if singleLine.count > truncateTo {
                    let idx = singleLine.index(singleLine.startIndex, offsetBy: truncateTo)
                    return String(singleLine[..<idx]) + "…"
                } else {
                    return singleLine
                }
            }.joined(separator: "\n")
            let skippedList = skippedBarcodes.map { entry -> String in
                let singleLine = entry.replacingOccurrences(of: "\n", with: " ")
                if singleLine.count > truncateTo {
                    let idx = singleLine.index(singleLine.startIndex, offsetBy: truncateTo)
                    return String(singleLine[..<idx]) + "…"
                } else {
                    return singleLine
                }
            }.joined(separator: "\n")

            var message = "Added \(addedCount)"
            if addedCount > 0 { message += "\n\n\(addedList)" }
            if skippedCount > 0 {
                message += "\n\nSkipped \(skippedCount)\n\n\(skippedList)"
            }
            duplicateSummaryMessage = message
            showDuplicateSummary = true
        }

        // Only save/dismiss here for non-identifier/manual or barcode flows; identifier lookup saves on confirm from preview
        if !(isManualEntry && useIdentifierLookup && !manualIdentifier.isEmpty) {
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
            if !newlyAdded.isEmpty {
                onDidAdd(newlyAdded)
            }
            if isManualEntry {
                withAnimation { isPresented = false }
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
                AlbumArtworkView(urlString: item.coverArtURL)
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
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingDeleteConfirmation = false
    
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
                        AlbumArtworkView(urlString: item.coverArtURL)
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
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Album?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                withAnimation {
                    viewContext.delete(item)
                    try? viewContext.save()
                }
            }
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete this album?")
        }
    }
}

// Renders album artwork from either a remote URL or a local file URL
struct AlbumArtworkView: View {
    let urlString: String?
    
    var body: some View {
        if let urlString = urlString, !urlString.isEmpty, let url = URL(string: urlString) {
            if url.isFileURL {
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                } else {
                    Color.gray
                }
            } else {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
            }
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 120))
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.2))
        }
    }
}

// Full-screen artwork with long-press save to Photos
struct FullScreenArtworkView: View {
    let urlString: String
    let onDismiss: () -> Void
    @State private var showingSaveDialog = false
    @State private var isSaving = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.9))
                            .padding()
                    }
                }
                Spacer(minLength: 0)
                AlbumArtworkView(urlString: urlString)
                    .scaledToFit()
                    .onLongPressGesture {
                        showingSaveDialog = true
                    }
                Spacer(minLength: 0)
            }
        }
        .confirmationDialog("Artwork", isPresented: $showingSaveDialog) {
            Button("Save Image to Photos") {
                Task { await saveImageToPhotos() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private func saveImageToPhotos() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard let url = URL(string: urlString) else { return }
        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (fetched, _) = try await URLSession.shared.data(from: url)
                data = fetched
            }
            guard let image = UIImage(data: data) else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        } catch {
            print("❌ Failed to save image to Photos: \(error)")
        }
    }
}

// UIKit wrapper to present native Photos picker immediately in a sheet
struct PhotoPickerView: UIViewControllerRepresentable {
    typealias UIViewControllerType = PHPickerViewController
    let onPicked: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (UIImage?) -> Void
        init(onPicked: @escaping (UIImage?) -> Void) { self.onPicked = onPicked }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                picker.dismiss(animated: true)
                self.onPicked(nil)
                return
            }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async {
                        picker.dismiss(animated: true)
                        self.onPicked(object as? UIImage)
                    }
                }
            } else {
                picker.dismiss(animated: true)
                self.onPicked(nil)
            }
        }
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

// MARK: - Identifier Lookup Preview
struct IdentifierLookupData {
    let coverUrl: URL?
    let artist: String?
    let title: String?
    let genre: String?
    let year: String?
    let tracklist: [DiscogsTrack]?
    let notes: String?
}

struct IdentifierLookupPreviewView: View {
    let preview: IdentifierLookupData
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let coverUrl = preview.coverUrl {
                        AsyncImage(url: coverUrl) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .cornerRadius(8)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    
                    Group {
                        Text(preview.artist ?? "Unknown Artist")
                            .font(.headline)
                        Text(preview.title ?? "Unknown Album")
                            .font(.title3)
                        if let year = preview.year { Text(year).foregroundColor(.secondary) }
                        if let genre = preview.genre { Text(genre).foregroundColor(.secondary) }
                        if let notes = preview.notes, !notes.isEmpty {
                            Text(notes).font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
                    
                    if let tracks = preview.tracklist, !tracks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tracks").font(.headline)
                            ForEach(tracks, id: \.position) { track in
                                HStack {
                                    Text(track.position).foregroundColor(.secondary).frame(width: 30, alignment: .leading)
                                    Text(track.title)
                                    Spacer()
                                    if !track.duration.isEmpty { Text(track.duration).foregroundColor(.secondary) }
                                }
                                Divider()
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Confirm Album")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") { onConfirm() }
                        .accessibilityIdentifier("confirmIdentifierAdd")
                }
            }
        }
    }
}

 
