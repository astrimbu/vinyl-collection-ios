# Vinyl Collection Manager for iOS

A beautiful iOS app to manage your vinyl record collection with advanced features for data entry, organization, and export.

## Features

### Core Functionality
- Browse and manage your vinyl collection with grid and list views
- Search through your collection by artist, album title, or genre
- Multiple sorting options (Artist A-Z/Z-A, Album A-Z/Z-A, Year newest/oldest)
- Track listing support with full album details
- Album artwork display from Discogs integration

### Data Entry
- **Barcode Scanning**: Scan vinyl barcodes using your device camera for instant album lookup
- **Manual Entry**: Add albums manually with all metadata fields
- **CSV Import**: Bulk import your existing collection from CSV files
- Automatic Discogs metadata fetching for missing information

### Export & Backup
- **Google Sheets Export**: Export your entire collection to Google Sheets with OAuth authentication
- Includes all album metadata (Title, Artist, Year, Genre, Notes)

### Advanced Features
- Automatic rate limiting for Discogs API compliance (60 requests per minute)
- Background data fetching for imported records
- Edit album information directly in the app
- Delete individual records or entire collection
- Modern iOS design with SwiftUI

## Setup

### Prerequisites

- Xcode 14.0 or later
- iOS 15.0 or later
- A Discogs API token
- (Optional) Google Cloud credentials for Sheets export

### Environment Setup

1. Copy the `.env.example` file to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Add your API credentials to the `.env` file:
   ```
   DISCOGS_API_TOKEN=your_discogs_token_here
   GOOGLE_CLIENT_ID=your_google_client_id_here
   GOOGLE_CLIENT_SECRET=your_google_client_secret_here
   GOOGLE_REDIRECT_URI=aeiou.Vinyls://oauth
   ```

### Getting API Credentials

#### Discogs API Token
1. Create a Discogs account at https://www.discogs.com
2. Go to your Developer settings
3. Generate a new personal access token

#### Google Sheets API (Optional)
1. Go to the [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project or select existing one
3. Enable the Google Sheets API
4. Create OAuth 2.0 credentials
5. Add `aeiou.Vinyls://oauth` as a redirect URI

### Building the Project

1. Open `Vinyls.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (⌘R)

## Usage

### Adding Records

#### Via Barcode Scanning
1. Tap the "+" button in the main view
2. Select "Barcode Scan" mode
3. Tap "Scan Barcode" and point camera at vinyl barcode
4. The app will automatically fetch album details from Discogs
5. Review and save the scanned records

#### Via Manual Entry
1. Tap the "+" button in the main view
2. Select "Manual Entry" mode
3. Fill in album information manually
4. Save to add to your collection

#### Via CSV Import
1. Tap the menu button (⋯) in the main view
2. Select "Import CSV"
3. Choose a CSV file with columns: Artist Name, Title, Identifiers, Notes
4. The app will import all records and fetch Discogs data in the background

### Exporting Data

#### Google Sheets Export
1. Tap the menu button (⋯) in the main view
2. Select "Export to Google Sheets"
3. Authenticate with your Google account
4. A new spreadsheet will be created with your entire collection

### Organizing Your Collection

- Use the search bar to find specific albums
- Sort by various criteria using the sort picker
- Switch between grid and list views
- Edit album details by tapping on a record and selecting "Edit"

## Architecture

The app follows modern iOS development practices:

- **SwiftUI** for the user interface
- **Core Data** for local data persistence
- **Async/await** for network operations
- **MVVM architecture** with ObservableObject view models
- **Discogs API integration** for metadata and artwork
- **Google Sheets API** for data export
- **AVFoundation** for barcode scanning
- **OAuth 2.0** for secure Google authentication

## Technical Features

- **Rate Limiting**: Automatic compliance with Discogs API limits
- **Background Processing**: Metadata fetching doesn't block the UI
- **Error Handling**: Graceful handling of network and API errors
- **Security**: Secure credential management with environment variables
- **Performance**: Efficient image loading and caching
- **Accessibility**: Full VoiceOver support for vision accessibility

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Related Projects

- [vinyl-collection](https://github.com/astrimbu/vinyl-collection) - Web version of the vinyl collection manager 