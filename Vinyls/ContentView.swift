//
//  ContentView.swift
//  Vinyls
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddRecordSheet = false
    @State private var showingImportCSVSheet = false
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
                    Button(action: { showingImportCSVSheet = true }) {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
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
}

struct RecordDetailView: View {
    let item: Item
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                if item.coverArtURL != "" {
                    AsyncImage(url: URL(string: item.coverArtURL ?? "")) { image in
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
                    HStack {
                        Text("Artist:")
                            .fontWeight(.bold)
                        Text(item.artist ?? "Unknown")
                    }
                    
                    HStack {
                        Text("Album:")
                            .fontWeight(.bold)
                        Text(item.albumTitle ?? "Unknown")
                    }
                    
                    HStack {
                        Text("Year:")
                            .fontWeight(.bold)
                        Text(item.releaseYear > 0 ? "\(item.releaseYear)" : "Unknown")
                    }
                    
                    HStack {
                        Text("Genre:")
                            .fontWeight(.bold)
                        Text(item.genre ?? "Unknown")
                    }
                    
                    HStack {
                        Text("Notes:")
                            .fontWeight(.bold)
                        Text(item.notes ?? "None")
                    }
                    
                    HStack {
                        Text("Identifier:")
                            .fontWeight(.bold)
                        Text(item.identifier ?? "None")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(item.albumTitle ?? "Record Details")
    }
}

struct AddRecordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var isPresented: Bool
    
    @State private var albumTitle = ""
    @State private var artist = ""
    @State private var genre = ""
    @State private var releaseYear = ""
    @State private var coverArtURL = ""
    @State private var notes = ""
    @State private var identifier = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Album Information")) {
                    TextField("Artist", text: $artist)
                    TextField("Album Title", text: $albumTitle)
                    TextField("Release Year", text: $releaseYear)
                        .keyboardType(.numberPad)
                        .onChange(of: releaseYear) { oldValue, newValue in
                            // Only allow digits in the release year field
                            if !newValue.isEmpty && Int(newValue) == nil {
                                releaseYear = oldValue
                            }
                        }
                    TextField("Genre", text: $genre)
                    TextField("Notes", text: $notes)
                    TextField("Identifier", text: $identifier)
                    TextField("Cover Art URL (optional)", text: $coverArtURL)
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
                        addRecord()
                        isPresented = false
                    }
                    .disabled(albumTitle.isEmpty || artist.isEmpty)
                }
            }
        }
    }
    
    private func addRecord() {
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
            newItem.artist = artist
            newItem.albumTitle = albumTitle
            newItem.genre = genre
            newItem.notes = notes.isEmpty ? nil : notes
            newItem.identifier = identifier.isEmpty ? nil : identifier
            
            if let year = Int16(releaseYear), year > 0 {
                newItem.releaseYear = year
            } else {
                newItem.releaseYear = 0
            }
            
            newItem.coverArtURL = coverArtURL

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// Extract record row view into a separate component
struct RecordRowView: View {
    let item: Item
    
    var body: some View {
        HStack {
            if item.coverArtURL != "" {
                AsyncImage(url: URL(string: item.coverArtURL ?? "")) { image in
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
    let item: Item
    
    var body: some View {
        NavigationLink {
            RecordDetailView(item: item)
        } label: {
            VStack {
                ZStack(alignment: .bottom) {
                    if item.coverArtURL != "" {
                        AsyncImage(url: URL(string: item.coverArtURL ?? "")) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray
                        }
                        .aspectRatio(1, contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .background(Color.gray.opacity(0.2))
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

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
