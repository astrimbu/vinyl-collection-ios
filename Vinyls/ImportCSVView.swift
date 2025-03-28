import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct ImportCSVView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discogsService = DiscogsService.shared
    
    @State private var isImporting = false
    @State private var importedCount = 0
    @State private var isShowingResult = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Import your vinyl collection from a CSV file")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Text("The CSV should contain columns for: Artist Name, Title, Identifiers, Notes, Weight, and Dupe")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Example format:")
                    .font(.subheadline)
                    .padding(.top)
                
                Text("Artist Name,Title,Identifiers,Notes,Dupe,Weight")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 5)
                
                Button(action: {
                    isImporting = true
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Select CSV File")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Import Collection")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.delimitedText, .text],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    do {
                        guard let selectedFile: URL = try result.get().first else { return }
                        
                        if selectedFile.startAccessingSecurityScopedResource() {
                            defer { selectedFile.stopAccessingSecurityScopedResource() }
                            
                            let data = try String(contentsOf: selectedFile, encoding: .utf8)
                            await importCSVData(data)
                        } else {
                            errorMessage = "Failed to access the file"
                            isShowingResult = true
                        }
                    } catch {
                        errorMessage = "Error importing file: \(error.localizedDescription)"
                        isShowingResult = true
                    }
                }
            }
            .alert(isPresented: $isShowingResult) {
                if let error = errorMessage {
                    return Alert(
                        title: Text("Import Failed"),
                        message: Text(error),
                        dismissButton: .default(Text("OK"))
                    )
                } else {
                    return Alert(
                        title: Text("Import Successful"),
                        message: Text("Successfully imported \(importedCount) vinyl records. Discogs data will be fetched in the background."),
                        dismissButton: .default(Text("OK")) {
                            dismiss()
                        }
                    )
                }
            }
        }
    }
    
    private func importCSVData(_ csvString: String) async {
        let rows = csvString.components(separatedBy: .newlines)
        guard rows.count > 1 else {
            errorMessage = "CSV file is empty or invalid"
            isShowingResult = true
            return
        }
        
        // Assume first row is headers
        let headers = parseCSVLine(rows[0])
        
        // Find column indices - check for closest matches
        func columnIndex(for possibleNames: [String]) -> Int? {
            for name in possibleNames {
                if let index = headers.firstIndex(where: { $0.lowercased().contains(name.lowercased()) }) {
                    return index
                }
            }
            return nil
        }
        
        let artistIndex = columnIndex(for: ["Artist Name", "Artist"])
        let titleIndex = columnIndex(for: ["Title", "Album Title", "Album"])
        let identifierIndex = columnIndex(for: ["Identifiers", "Identifier", "Cat #", "Catalog"])
        let notesIndex = columnIndex(for: ["Notes", "Note", "Comment"])
        
        if artistIndex == nil && titleIndex == nil {
            errorMessage = "CSV must contain either Artist or Title columns"
            isShowingResult = true
            return
        }
        
        // Start from index 1 to skip headers
        importedCount = 0
        var importedItems: [Item] = []
        
        await viewContext.perform {
            for i in 1..<rows.count {
                let rowString = rows[i]
                if rowString.isEmpty { continue }
                
                // Parse the CSV line properly handling quotes
                let columns = parseCSVLine(rowString)
                if columns.isEmpty { continue }
                
                let newItem = Item(context: viewContext)
                newItem.timestamp = Date()
                
                // Default values
                newItem.artist = "Unknown Artist"
                newItem.albumTitle = "Unknown Album"
                newItem.genre = "Unknown"
                newItem.notes = nil
                newItem.identifier = nil
                
                // Set the artist
                if let idx = artistIndex, idx < columns.count {
                    newItem.artist = columns[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Set the album title
                if let idx = titleIndex, idx < columns.count {
                    newItem.albumTitle = columns[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Set the identifier
                if let idx = identifierIndex, idx < columns.count {
                    let identifierText = columns[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !identifierText.isEmpty {
                        newItem.identifier = identifierText
                    }
                }
                
                // Set the notes
                if let idx = notesIndex, idx < columns.count {
                    let notesText = columns[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notesText.isEmpty {
                        newItem.notes = notesText
                    }
                }
                
                importedItems.append(newItem)
                importedCount += 1
            }
            
            do {
                try viewContext.save()
                
                // Start background fetch of Discogs data
                Task(priority: .background) {
                    await fetchDiscogsDataInBackground(for: importedItems)
                }
                
                // Show success message and dismiss
                isShowingResult = true
            } catch {
                errorMessage = "Failed to save imported data: \(error.localizedDescription)"
                isShowingResult = true
            }
        }
    }
    
    private func fetchDiscogsDataInBackground(for items: [Item]) async {
        guard !items.isEmpty else { return }
        
        for item in items {
            // Fetch Discogs data
            let (artworkUrl, tracks) = await discogsService.fetchAlbumDetails(
                artist: item.artist ?? "",
                title: item.albumTitle ?? ""
            )
            
            // Update the item with fetched data
            await viewContext.perform {
                if let artworkUrl = artworkUrl {
                    item.coverArtURL = artworkUrl.absoluteString
                }
                
                if !tracks.isEmpty {
                    do {
                        let tracksData = try JSONEncoder().encode(tracks)
                        item.tracklist = tracksData
                    } catch {
                        print("Failed to encode tracks data: \(error)")
                    }
                }
                
                try? viewContext.save()
            }
            
            // Respect rate limits by waiting between requests
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay between requests
        }
    }
    
    // Function to properly parse CSV lines handling quoted values
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var currentValue = ""
        var insideQuotes = false
        
        for character in line {
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == "," && !insideQuotes {
                result.append(currentValue)
                currentValue = ""
            } else {
                currentValue.append(character)
            }
        }
        
        // Add the last value
        result.append(currentValue)
        
        return result
    }
}

struct ImportCSVView_Previews: PreviewProvider {
    static var previews: some View {
        ImportCSVView()
    }
} 